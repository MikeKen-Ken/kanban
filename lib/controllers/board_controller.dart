import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../features/project/project_list_preferences.dart';
import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../models/kanban_models.dart';
import '../features/kanban/kanban_labels.dart';
import '../settings/app_settings.dart';
import '../webdav_sync/webdav_config.dart';
import '../webdav_sync/webdav_sync_service.dart';

class BoardController extends ChangeNotifier {
  BoardController._({
    required BoardRepository repository,
    required WebDavSyncService syncService,
  })  : _repository = repository,
        _syncService = syncService;

  final BoardRepository _repository;
  final WebDavSyncService _syncService;

  KanbanBoard? board;
  ProjectsManifest? manifest;
  String? activeProjectId;
  ProjectSettings projectSettings = const ProjectSettings();
  WebDavConfig webDavConfig = WebDavConfig.empty;
  AppSettings appSettings = AppSettings.platformDefault();
  bool isLoading = true;
  String? errorMessage;

  SyncStatus get syncStatus => _syncService.status;
  String? get syncError => _syncService.lastError;
  DateTime? get lastSyncedAt => _syncService.lastSyncedAt;
  Stream<SyncStatus> get syncStatusStream => _syncService.statusStream;

  List<ProjectEntry> get projects {
    final entries = manifest?.projects ?? const <ProjectEntry>[];
    return sortProjectEntries(
      entries,
      sortMode: appSettings.projectSortMode,
      pinnedProjectIds: appSettings.pinnedProjectIds,
      lastUsedAtByProjectId: appSettings.projectLastUsedAt,
    );
  }

  bool isProjectPinned(String projectId) =>
      appSettings.pinnedProjectIds.contains(projectId);

  ProjectEntry? get activeProject {
    if (activeProjectId == null || manifest == null) return null;
    return manifest!.findById(activeProjectId!);
  }

  static Future<BoardController> create() async {
    final prefs = await SharedPreferences.getInstance();
    final repository = BoardRepository(prefs);
    late BoardController controller;
    final syncService = WebDavSyncService(
      loadConfig: () async => controller.webDavConfig,
      loadWorkspace: () async => controller._loadWorkspaceSnapshot(),
      saveWorkspace: (workspace) async =>
          controller._applyWorkspaceSnapshot(workspace),
    );
    controller = BoardController._(
      repository: repository,
      syncService: syncService,
    );
    await controller._init();
    return controller;
  }

  Future<ProjectWorkspaceSnapshot> _loadWorkspaceSnapshot() async {
    final manifest = await _repository.loadManifest();
    final boards = <String, KanbanBoard>{};
    final settings = <String, ProjectSettings>{};

    for (final entry in manifest.projects) {
      if (await _repository.storage.hasProjectBoard(entry.id)) {
        boards[entry.id] = await _repository.loadBoard(entry.id);
      }
      settings[entry.id] = await _repository.loadProjectSettings(entry.id);
    }

    return ProjectWorkspaceSnapshot(
      manifest: manifest,
      boards: boards,
      settings: settings,
    );
  }

  Future<void> _applyWorkspaceSnapshot(
    ProjectWorkspaceSnapshot workspace,
  ) async {
    await _repository.saveManifest(workspace.manifest);
    for (final entry in workspace.manifest.projects) {
      final board = workspace.boards[entry.id];
      final settings = workspace.settings[entry.id];
      if (board != null) {
        await _repository.saveBoard(entry.id, board);
      }
      if (settings != null) {
        await _repository.saveProjectSettings(entry.id, settings);
      }
    }

    manifest = workspace.manifest;
    final currentId = activeProjectId;
    if (currentId != null && workspace.manifest.findById(currentId) != null) {
      board = workspace.boards[currentId];
      projectSettings =
          workspace.settings[currentId] ?? const ProjectSettings();
    } else if (workspace.manifest.projects.isNotEmpty) {
      final first = workspace.manifest.projects.first;
      activeProjectId = first.id;
      await _repository.saveActiveProjectId(first.id);
      board = workspace.boards[first.id];
      projectSettings =
          workspace.settings[first.id] ?? const ProjectSettings();
    }
  }

  Future<void> _init() async {
    try {
      webDavConfig = await _repository.loadWebDavConfig();
      appSettings = _repository.loadAppSettings();
      await _repository.ensureInitialized();

      manifest = await _repository.loadManifest();
      activeProjectId = _repository.loadActiveProjectId();

      if (activeProjectId == null ||
          manifest!.findById(activeProjectId!) == null) {
        activeProjectId = manifest!.projects.first.id;
        await _repository.saveActiveProjectId(activeProjectId!);
      }

      board = await _repository.loadBoard(activeProjectId!);
      projectSettings =
          await _repository.loadProjectSettings(activeProjectId!);

      if (webDavConfig.enabled && webDavConfig.isConfigured) {
        await _syncService.pullAndMerge();
        manifest = await _repository.loadManifest();
        board = await _repository.loadBoard(activeProjectId!);
        projectSettings =
            await _repository.loadProjectSettings(activeProjectId!);
        _syncService.startPolling();
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _persistAndSync(KanbanBoard next) async {
    if (activeProjectId == null) return;
    board = next;
    await _repository.saveBoard(activeProjectId!, next);
    await _updateManifestEntry(title: next.title);
    notifyListeners();
    _syncService.schedulePush();
  }

  Future<void> _persistProjectSettings(ProjectSettings next) async {
    if (activeProjectId == null) return;
    projectSettings = next;
    await _repository.saveProjectSettings(activeProjectId!, next);
    notifyListeners();
    _syncService.schedulePush();
  }

  Future<void> _updateManifestEntry({String? title}) async {
    if (manifest == null || activeProjectId == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final projects = manifest!.projects.map((entry) {
      if (entry.id != activeProjectId) return entry;
      return entry.copyWith(
        title: title ?? entry.title,
        updatedAt: now,
        revision: entry.revision + 1,
      );
    }).toList();
    manifest = manifest!.bump().copyWith(projects: projects);
    await _repository.saveManifest(manifest!);
  }

  KanbanBoard _bump(KanbanBoard current) {
    return current.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      revision: current.revision + 1,
    );
  }

  List<KanbanColumn> _normalizeOrders(List<KanbanColumn> columns) {
    return columns.map((col) {
      final sorted = [...col.cards]..sort((a, b) => a.order.compareTo(b.order));
      final cards = [
        for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(order: i),
      ];
      return col.copyWith(cards: cards);
    }).toList();
  }

  KanbanColumn? _findDoneColumn(KanbanBoard current) {
    final doneName = projectSettings.doneColumnName;
    for (final col in current.columns) {
      if (col.id == 'done') return col;
    }
    for (final col in current.columns) {
      if (col.title == doneName) return col;
    }
    for (final col in current.columns) {
      if (col.title.contains('完成')) return col;
    }
    return null;
  }

  Future<void> switchProject(String projectId) async {
    if (manifest?.findById(projectId) == null) return;
    if (projectId == activeProjectId) return;

    activeProjectId = projectId;
    await _repository.saveActiveProjectId(projectId);
    board = await _repository.loadBoard(projectId);
    projectSettings = await _repository.loadProjectSettings(projectId);
    await _recordProjectUsed(projectId);
    notifyListeners();
  }

  Future<void> createProject(String title) async {
    final projectId = await _repository.createProject(title);
    manifest = await _repository.loadManifest();
    await switchProject(projectId);
    _syncService.schedulePush();
  }

  Future<void> renameActiveProject(String title) async {
    await updateTitle(title);
  }

  Future<void> saveProjectSettings(ProjectSettings settings) async {
    if (board == null) return;
    final bumped = settings.bump();
    final oldName = projectSettings.doneColumnName;
    final newName = bumped.doneColumnName;

    if (oldName != newName) {
      final doneColumn = _findDoneColumn(board!);
      if (doneColumn != null && doneColumn.title != newName) {
        await renameColumn(doneColumn.id, newName);
      }
    }

    await _persistProjectSettings(bumped);
  }

  Future<void> updateTitle(String title) async {
    if (board == null) return;
    await _persistAndSync(_bump(board!.copyWith(title: title)));
  }

  Future<void> addColumn(String title) async {
    if (board == null) return;
    final columns = [...board!.columns];
    columns.add(
      KanbanColumn(
        id: const Uuid().v4(),
        title: title,
        order: columns.length,
        cards: [],
      ),
    );
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> renameColumn(String columnId, String title) async {
    if (board == null) return;
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      return col.copyWith(title: title);
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> updateColumnColor(String columnId, int? colorValue) async {
    if (board == null) return;
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      return col.copyWith(colorValue: colorValue);
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    appSettings = settings;
    await _repository.saveAppSettings(settings);
    notifyListeners();
  }

  Future<void> setProjectSortMode(ProjectSortMode mode) async {
    if (mode == appSettings.projectSortMode) return;
    await saveAppSettings(appSettings.copyWith(projectSortMode: mode));
  }

  Future<void> toggleProjectPin(String projectId) async {
    if (manifest?.findById(projectId) == null) return;
    final pinned = [...appSettings.pinnedProjectIds];
    if (pinned.contains(projectId)) {
      pinned.remove(projectId);
    } else {
      pinned.insert(0, projectId);
    }
    await saveAppSettings(appSettings.copyWith(pinnedProjectIds: pinned));
  }

  Future<void> _recordProjectUsed(String projectId) async {
    final lastUsed = Map<String, int>.from(appSettings.projectLastUsedAt);
    lastUsed[projectId] = DateTime.now().millisecondsSinceEpoch;
    appSettings = appSettings.copyWith(projectLastUsedAt: lastUsed);
    await _repository.saveAppSettings(appSettings);
  }

  Future<void> deleteColumn(String columnId) async {
    if (board == null) return;
    final columns =
        board!.columns.where((col) => col.id != columnId).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> addCard(String columnId, String title, {String? description}) async {
    if (board == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      final cards = [
        ...col.cards,
        KanbanCard(
          id: const Uuid().v4(),
          title: title,
          description: description,
          order: col.cards.length,
          createdAt: now,
        ),
      ];
      return col.copyWith(cards: cards);
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> updateCard(
    String columnId,
    String cardId, {
    String? title,
    String? description,
  }) async {
    await updateCardFull(
      columnId,
      cardId,
      title: title,
      description: description,
    );
  }

  Future<void> updateCardFull(
    String columnId,
    String cardId, {
    String? title,
    String? description,
    bool? completed,
    int? dueDate,
    bool clearDueDate = false,
    CardPriority? priority,
    List<String>? labels,
    List<ChecklistItem>? checklist,
  }) async {
    if (board == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      final cards = col.cards.map((card) {
        if (card.id != cardId) return card;
        final nextCompleted = completed ?? card.completed;
        return card.copyWith(
          title: title ?? card.title,
          description: description ?? card.description,
          completed: nextCompleted,
          completedAt: nextCompleted
              ? (card.completedAt ?? now)
              : null,
          dueDate: clearDueDate ? null : (dueDate ?? card.dueDate),
          priority: priority ?? card.priority,
          labels: labels ?? card.labels,
          checklist: checklist ?? card.checklist,
        );
      }).toList();
      return col.copyWith(cards: cards);
    }).toList();
    await _persistAndSync(
      _bump(board!.copyWith(columns: _normalizeOrders(columns))),
    );
  }

  Future<void> toggleCardCompleted(String columnId, String cardId) async {
    if (board == null) return;
    final current = board!;
    KanbanCard? target;
    for (final col in current.columns) {
      for (final card in col.cards) {
        if (col.id == columnId && card.id == cardId) {
          target = card;
          break;
        }
      }
    }
    if (target == null) return;

    final nextCompleted = !target.completed;
    final now = DateTime.now().millisecondsSinceEpoch;
    final doneColumn = _findDoneColumn(current);

    if (nextCompleted && doneColumn != null && doneColumn.id != columnId) {
      await moveCard(
        cardId: cardId,
        fromColumnId: columnId,
        toColumnId: doneColumn.id,
        toIndex: doneColumn.cards.length,
        completed: true,
        completedAt: now,
      );
      return;
    }

    if (!nextCompleted && doneColumn?.id == columnId) {
      final todoColumn = current.columns.cast<KanbanColumn?>().firstWhere(
            (col) => col!.id == 'todo',
            orElse: () => current.columns.isNotEmpty
                ? current.columns.first
                : null,
          );
      if (todoColumn != null && todoColumn.id != columnId) {
        await moveCard(
          cardId: cardId,
          fromColumnId: columnId,
          toColumnId: todoColumn.id,
          toIndex: todoColumn.cards.length,
          completed: false,
          completedAt: null,
        );
        return;
      }
    }

    await updateCardFull(columnId, cardId, completed: nextCompleted);
  }

  Future<void> deleteCard(String columnId, String cardId) async {
    if (board == null) return;
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      final cards = col.cards.where((c) => c.id != cardId).toList();
      return col.copyWith(cards: cards);
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> moveCard({
    required String cardId,
    required String fromColumnId,
    required String toColumnId,
    required int toIndex,
    bool? completed,
    int? completedAt,
  }) async {
    if (board == null) return;

    int? fromIndex;
    if (fromColumnId == toColumnId) {
      final source = board!.columns.firstWhere((c) => c.id == fromColumnId);
      fromIndex = source.cards.indexWhere((c) => c.id == cardId);
    }

    KanbanCard? moving;
    final stripped = board!.columns.map((col) {
      if (col.id != fromColumnId) return col;
      final remaining = <KanbanCard>[];
      for (final card in col.cards) {
        if (card.id == cardId) {
          moving = card;
        } else {
          remaining.add(card);
        }
      }
      return col.copyWith(cards: remaining);
    }).toList();

    if (moving == null) return;

    final doneColumn = _findDoneColumn(board!);
    var cardToInsert = moving!;
    if (completed != null) {
      cardToInsert = cardToInsert.copyWith(
        completed: completed,
        completedAt: completedAt,
      );
    } else if (doneColumn != null) {
      final markDone = toColumnId == doneColumn.id;
      cardToInsert = cardToInsert.copyWith(
        completed: markDone,
        completedAt: markDone
            ? (cardToInsert.completedAt ??
                DateTime.now().millisecondsSinceEpoch)
            : null,
      );
    }

    final inserted = stripped.map((col) {
      if (col.id != toColumnId) return col;
      final cards = [...col.cards];
      var index = toIndex.clamp(0, cards.length);
      if (fromColumnId == toColumnId &&
          fromIndex != null &&
          fromIndex >= 0 &&
          fromIndex < index) {
        index -= 1;
      }
      cards.insert(index, cardToInsert);
      return col.copyWith(cards: cards);
    }).toList();

    await _persistAndSync(
      _bump(board!.copyWith(columns: _normalizeOrders(inserted))),
    );
  }

  Future<void> saveWebDavConfig(WebDavConfig config) async {
    webDavConfig = config;
    await _repository.saveWebDavConfig(config);
    if (config.enabled && config.isConfigured) {
      _syncService.startPolling();
      await _syncService.pullAndMerge();
      manifest = await _repository.loadManifest();
      if (activeProjectId != null) {
        board = await _repository.loadBoard(activeProjectId!);
        projectSettings =
            await _repository.loadProjectSettings(activeProjectId!);
      }
    } else {
      _syncService.stopPolling();
    }
    notifyListeners();
  }

  Future<bool> testWebDav(WebDavConfig config) {
    return _syncService.testConnection(config);
  }

  Future<void> syncNow() async {
    await _syncService.pullAndMerge();
    manifest = await _repository.loadManifest();
    if (activeProjectId != null) {
      board = await _repository.loadBoard(activeProjectId!);
      projectSettings =
          await _repository.loadProjectSettings(activeProjectId!);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _syncService.dispose();
    super.dispose();
  }
}
