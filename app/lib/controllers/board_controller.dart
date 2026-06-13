import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../features/project/project_list_preferences.dart';
import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../models/kanban_models.dart';
import '../features/kanban/column_card_preferences.dart';
import '../features/kanban/kanban_labels.dart';
import '../features/trash/trash_models.dart';
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
  TrashBin activeProjectTrash = TrashBin.empty;
  TrashBin appTrash = TrashBin.empty;
  Map<String, TrashBin> projectTrashes = {};
  List<TrashItem> labelTrash = const [];
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

  /// 所有回收站条目（当前项目 + 已删项目 + 标签），按删除时间倒序
  List<TrashItem> get allTrashItems {
    final items = <TrashItem>[
      ...activeProjectTrash.items,
      ...appTrash.items,
      ...labelTrash,
    ];
    for (final entry in projectTrashes.entries) {
      if (entry.key == activeProjectId) continue;
      final projectTitle = manifest?.findById(entry.key)?.title;
      for (final item in entry.value.items) {
        items.add(
          item.copyWith(
            projectTitle: item.projectTitle ?? projectTitle,
          ),
        );
      }
    }
    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  int get trashItemCount => allTrashItems.length;

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
    final projectTrash = <String, TrashBin>{};

    for (final entry in manifest.projects) {
      if (await _repository.storage.hasProjectBoard(entry.id)) {
        boards[entry.id] = await _repository.loadBoard(entry.id);
      }
      settings[entry.id] = await _repository.loadProjectSettings(entry.id);
      projectTrash[entry.id] = await _repository.loadProjectTrash(entry.id);
    }

    return ProjectWorkspaceSnapshot(
      manifest: manifest,
      boards: boards,
      settings: settings,
      projectTrash: projectTrash,
      appTrash: await _repository.loadAppTrash(),
    );
  }

  Future<void> _applyWorkspaceSnapshot(
    ProjectWorkspaceSnapshot workspace,
  ) async {
    await _repository.saveManifest(workspace.manifest);
    for (final entry in workspace.manifest.projects) {
      final board = workspace.boards[entry.id];
      final settings = workspace.settings[entry.id];
      final trash = workspace.projectTrash[entry.id];
      if (board != null) {
        await _repository.saveBoard(entry.id, board);
      }
      if (settings != null) {
        await _repository.saveProjectSettings(entry.id, settings);
      }
      if (trash != null) {
        await _repository.saveProjectTrash(entry.id, trash);
      }
    }
    await _repository.saveAppTrash(workspace.appTrash);

    manifest = workspace.manifest;
    projectTrashes = Map<String, TrashBin>.from(workspace.projectTrash);
    appTrash = workspace.appTrash;
    final currentId = activeProjectId;
    if (currentId != null && workspace.manifest.findById(currentId) != null) {
      board = workspace.boards[currentId];
      projectSettings =
          workspace.settings[currentId] ?? const ProjectSettings();
      activeProjectTrash =
          workspace.projectTrash[currentId] ?? TrashBin.empty;
    } else if (workspace.manifest.projects.isNotEmpty) {
      final first = workspace.manifest.projects.first;
      activeProjectId = first.id;
      await _repository.saveActiveProjectId(first.id);
      board = workspace.boards[first.id];
      projectSettings =
          workspace.settings[first.id] ?? const ProjectSettings();
      activeProjectTrash =
          workspace.projectTrash[first.id] ?? TrashBin.empty;
    }
  }

  Future<void> _loadTrashState() async {
    appTrash = await _repository.loadAppTrash();
    labelTrash = _repository.loadLabelTrash();
    projectTrashes = {};
    if (manifest != null) {
      for (final entry in manifest!.projects) {
        projectTrashes[entry.id] =
            await _repository.loadProjectTrash(entry.id);
      }
    }
    if (activeProjectId != null) {
      activeProjectTrash =
          projectTrashes[activeProjectId!] ?? TrashBin.empty;
    } else {
      activeProjectTrash = TrashBin.empty;
    }
  }

  Future<void> _persistActiveProjectTrash() async {
    if (activeProjectId == null) return;
    projectTrashes[activeProjectId!] = activeProjectTrash;
    await _repository.saveProjectTrash(activeProjectId!, activeProjectTrash);
    notifyListeners();
    _syncService.schedulePush();
  }

  Future<void> _persistAppTrash() async {
    await _repository.saveAppTrash(appTrash);
    notifyListeners();
    _syncService.schedulePush();
  }

  Future<void> _persistLabelTrash() async {
    await _repository.saveLabelTrash(labelTrash);
    notifyListeners();
  }

  Future<void> _addToActiveProjectTrash(TrashItem item) async {
    activeProjectTrash = activeProjectTrash.bump().copyWith(
          items: [item, ...activeProjectTrash.items],
        );
    await _persistActiveProjectTrash();
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
      await _loadTrashState();
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }

    if (webDavConfig.enabled && webDavConfig.isConfigured) {
      _syncService.startPolling();
      unawaited(_syncInBackground());
    }
  }

  Future<void> _syncInBackground() async {
    try {
      await _syncService.pullAndMerge();
      manifest = await _repository.loadManifest();
      if (activeProjectId != null) {
        board = await _repository.loadBoard(activeProjectId!);
        projectSettings =
            await _repository.loadProjectSettings(activeProjectId!);
        await _loadTrashState();
      }
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
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
      final prefs = columnPreferencesFor(col.id);
      if (prefs.sortMode != CardSortMode.custom) {
        return col;
      }

      final unpinned = col.cards
          .where((card) => !prefs.pinnedCardIds.contains(card.id))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      final orderMap = {
        for (var i = 0; i < unpinned.length; i++) unpinned[i].id: i,
      };
      final cards = col.cards
          .map(
            (card) => orderMap.containsKey(card.id)
                ? card.copyWith(order: orderMap[card.id]!)
                : card,
          )
          .toList();
      return col.copyWith(cards: cards);
    }).toList();
  }

  ColumnCardPreferences columnPreferencesFor(String columnId) =>
      projectSettings.columnPreferencesFor(columnId);

  List<KanbanCard> displayCardsForColumn(KanbanColumn column) {
    final prefs = columnPreferencesFor(column.id);
    return sortColumnCards(
      column.cards,
      sortMode: prefs.sortMode,
      pinnedCardIds: prefs.pinnedCardIds,
    );
  }

  bool isCardPinned(String columnId, String cardId) =>
      columnPreferencesFor(columnId).pinnedCardIds.contains(cardId);

  Future<void> _saveColumnPreferences(
    String columnId,
    ColumnCardPreferences prefs,
  ) async {
    final next = Map<String, ColumnCardPreferences>.from(
      projectSettings.columnPreferences,
    );
    next[columnId] = prefs;
    await _persistProjectSettings(
      projectSettings.bump().copyWith(columnPreferences: next),
    );
  }

  Future<void> setColumnSortMode(String columnId, CardSortMode mode) async {
    final current = columnPreferencesFor(columnId);
    if (current.sortMode == mode) return;
    await _saveColumnPreferences(
      columnId,
      current.copyWith(sortMode: mode),
    );
  }

  Future<void> toggleCardPin(String columnId, String cardId) async {
    if (board == null) return;
    final column = board!.columns.cast<KanbanColumn?>().firstWhere(
          (col) => col!.id == columnId,
          orElse: () => null,
        );
    if (column == null || !column.cards.any((card) => card.id == cardId)) {
      return;
    }

    final prefs = columnPreferencesFor(columnId);
    final pinned = [...prefs.pinnedCardIds];
    if (pinned.contains(cardId)) {
      pinned.remove(cardId);
    } else {
      pinned.insert(0, cardId);
    }
    await _saveColumnPreferences(columnId, prefs.copyWith(pinnedCardIds: pinned));
  }

  ({List<String> pinned, Map<String, int> orders}) _pinnedAndOrdersFromDisplay(
    List<KanbanCard> display,
    List<String> pinnedCardIds,
  ) {
    final pinned = <String>[];
    final orders = <String, int>{};
    var order = 0;
    for (final card in display) {
      if (pinnedCardIds.contains(card.id)) {
        pinned.add(card.id);
      } else {
        orders[card.id] = order++;
      }
    }
    return (pinned: pinned, orders: orders);
  }

  List<KanbanCard> _applyPinnedAndOrders(
    List<KanbanCard> cards,
    Map<String, int> orders,
    int updatedAt,
    String? touchedCardId,
  ) {
    return cards
        .map(
          (card) => card.copyWith(
            order: orders[card.id] ?? card.order,
            updatedAt: card.id == touchedCardId ? updatedAt : card.updatedAt,
          ),
        )
        .toList();
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
    activeProjectTrash = projectTrashes[projectId] ?? TrashBin.empty;
    await _recordProjectUsed(projectId);
    notifyListeners();
  }

  Future<void> createProject(String title) async {
    final projectId = await _repository.createProject(title);
    manifest = await _repository.loadManifest();
    projectTrashes[projectId] = TrashBin.empty;
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

  Future<String> addCustomLabel(String name, int colorValue) async {
    final key = const Uuid().v4();
    final label = KanbanLabel(
      key: key,
      name: name,
      color: Color(colorValue),
    );
    await saveAppSettings(
      appSettings.copyWith(
        customLabels: [...appSettings.customLabels, label],
      ),
    );
    return key;
  }

  Future<void> removeCustomLabel(String key) async {
    final label = appSettings.customLabels.cast<KanbanLabel?>().firstWhere(
          (item) => item!.key == key,
          orElse: () => null,
        );
    if (label == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    labelTrash = [
      TrashItem.forCustomLabel(
        trashId: const Uuid().v4(),
        deletedAt: now,
        label: label,
      ),
      ...labelTrash,
    ];
    await _persistLabelTrash();

    await saveAppSettings(
      appSettings.copyWith(
        customLabels:
            appSettings.customLabels.where((l) => l.key != key).toList(),
      ),
    );
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
    if (board == null || activeProjectId == null) return;
    final column = board!.columns.cast<KanbanColumn?>().firstWhere(
          (col) => col!.id == columnId,
          orElse: () => null,
        );
    if (column == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await _addToActiveProjectTrash(
      TrashItem.forColumn(
        trashId: const Uuid().v4(),
        deletedAt: now,
        projectId: activeProjectId!,
        projectTitle: board!.title,
        column: column,
      ),
    );

    final columns =
        board!.columns.where((col) => col.id != columnId).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<bool> deleteProject(String projectId) async {
    if (manifest == null || manifest!.projects.length <= 1) return false;

    final entry = manifest!.findById(projectId);
    if (entry == null) return false;

    final projectBoard = projectId == activeProjectId
        ? board!
        : await _repository.loadBoard(projectId);
    final settings = projectId == activeProjectId
        ? projectSettings
        : await _repository.loadProjectSettings(projectId);
    final trash =
        projectTrashes[projectId] ?? await _repository.loadProjectTrash(projectId);

    final now = DateTime.now().millisecondsSinceEpoch;
    appTrash = appTrash.bump().copyWith(
          items: [
            TrashItem.forProject(
              trashId: const Uuid().v4(),
              deletedAt: now,
              entry: entry,
              board: projectBoard,
              settings: settings,
              projectTrash: trash,
            ),
            ...appTrash.items,
          ],
        );

    final remaining =
        manifest!.projects.where((p) => p.id != projectId).toList();
    manifest = manifest!.bump().copyWith(projects: remaining);
    await _repository.saveManifest(manifest!);
    projectTrashes.remove(projectId);

    if (activeProjectId == projectId) {
      final next = remaining.first;
      activeProjectId = next.id;
      await _repository.saveActiveProjectId(next.id);
      board = await _repository.loadBoard(next.id);
      projectSettings = await _repository.loadProjectSettings(next.id);
      activeProjectTrash = projectTrashes[next.id] ?? TrashBin.empty;
    }

    await _persistAppTrash();
    notifyListeners();
    return true;
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
          updatedAt: now,
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
    int? colorValue,
    bool clearColor = false,
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
          colorValue: clearColor ? null : (colorValue ?? card.colorValue),
          updatedAt: now,
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
        toDisplayIndex: doneColumn.cards.length,
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
          toDisplayIndex: todoColumn.cards.length,
          completed: false,
          completedAt: null,
        );
        return;
      }
    }

    await updateCardFull(columnId, cardId, completed: nextCompleted);
  }

  Future<void> deleteCard(String columnId, String cardId) async {
    if (board == null || activeProjectId == null) return;

    KanbanCard? target;
    KanbanColumn? sourceColumn;
    for (final col in board!.columns) {
      if (col.id != columnId) continue;
      sourceColumn = col;
      for (final card in col.cards) {
        if (card.id == cardId) {
          target = card;
          break;
        }
      }
    }
    if (target == null || sourceColumn == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await _addToActiveProjectTrash(
      TrashItem.forCard(
        trashId: const Uuid().v4(),
        deletedAt: now,
        projectId: activeProjectId!,
        projectTitle: board!.title,
        columnId: columnId,
        columnTitle: sourceColumn.title,
        card: target,
      ),
    );

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
    required int toDisplayIndex,
    bool? completed,
    int? completedAt,
  }) async {
    if (board == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final fromPrefs = columnPreferencesFor(fromColumnId);
    final toPrefs = columnPreferencesFor(toColumnId);

    if (fromColumnId == toColumnId &&
        fromPrefs.sortMode != CardSortMode.custom) {
      return;
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
        updatedAt: now,
      );
    } else if (doneColumn != null) {
      final markDone = toColumnId == doneColumn.id;
      cardToInsert = cardToInsert.copyWith(
        completed: markDone,
        completedAt: markDone
            ? (cardToInsert.completedAt ?? now)
            : null,
        updatedAt: now,
      );
    } else {
      cardToInsert = cardToInsert.copyWith(updatedAt: now);
    }

    var nextPinnedByColumn = Map<String, ColumnCardPreferences>.from(
      projectSettings.columnPreferences,
    );

    if (fromColumnId != toColumnId) {
      final fromPinned = [...fromPrefs.pinnedCardIds]..remove(cardId);
      nextPinnedByColumn[fromColumnId] =
          fromPrefs.copyWith(pinnedCardIds: fromPinned);
    }

    final inserted = stripped.map((col) {
      if (col.id != toColumnId) return col;

      if (toPrefs.sortMode != CardSortMode.custom) {
        final cards = [
          ...col.cards,
          cardToInsert.copyWith(order: col.cards.length),
        ];
        return col.copyWith(cards: cards);
      }

      final targetPinned =
          nextPinnedByColumn[toColumnId]?.pinnedCardIds ?? toPrefs.pinnedCardIds;
      final pinnedCount = pinnedCardCount(targetPinned, col.cards);
      var display = sortColumnCards(
        col.cards,
        sortMode: CardSortMode.custom,
        pinnedCardIds: targetPinned,
      );

      var index = toDisplayIndex.clamp(0, display.length);
      final movingPinned = targetPinned.contains(cardId);
      if (movingPinned) {
        index = index.clamp(0, pinnedCount);
      } else {
        index = index.clamp(pinnedCount, display.length);
      }

      if (fromColumnId == toColumnId) {
        final before = sortColumnCards(
          [...col.cards, cardToInsert],
          sortMode: CardSortMode.custom,
          pinnedCardIds: targetPinned,
        );
        final oldIndex = before.indexWhere((card) => card.id == cardId);
        if (oldIndex >= 0 && oldIndex < index) {
          index -= 1;
        }
      }

      display = [...display]..insert(index, cardToInsert);
      final derived = _pinnedAndOrdersFromDisplay(display, targetPinned);
      final cards = _applyPinnedAndOrders(
        [
          ...col.cards.where((card) => card.id != cardId),
          cardToInsert,
        ],
        derived.orders,
        now,
        cardId,
      );

      nextPinnedByColumn[toColumnId] = (nextPinnedByColumn[toColumnId] ??
              toPrefs)
          .copyWith(pinnedCardIds: derived.pinned);

      return col.copyWith(cards: cards);
    }).toList();

    if (nextPinnedByColumn != projectSettings.columnPreferences) {
      projectSettings = projectSettings.bump().copyWith(
            columnPreferences: nextPinnedByColumn,
          );
      if (activeProjectId != null) {
        await _repository.saveProjectSettings(activeProjectId!, projectSettings);
      }
    }

    await _persistAndSync(
      _bump(board!.copyWith(columns: _normalizeOrders(inserted))),
    );
  }

  Future<String?> restoreTrashItem(String trashItemId) async {
    final labelIndex = labelTrash.indexWhere((item) => item.id == trashItemId);
    if (labelIndex >= 0) {
      return _restoreLabel(labelTrash[labelIndex]);
    }

    final appIndex = appTrash.items.indexWhere((item) => item.id == trashItemId);
    if (appIndex >= 0) {
      return _restoreProject(appTrash.items[appIndex]);
    }

    for (final entry in projectTrashes.entries) {
      final index =
          entry.value.items.indexWhere((item) => item.id == trashItemId);
      if (index >= 0) {
        return _restoreProjectItem(entry.key, entry.value.items[index]);
      }
    }

    return '未找到该回收项';
  }

  Future<void> permanentlyDeleteTrashItem(String trashItemId) async {
    if (labelTrash.any((item) => item.id == trashItemId)) {
      labelTrash = labelTrash.where((item) => item.id != trashItemId).toList();
      await _persistLabelTrash();
      notifyListeners();
      return;
    }

    if (appTrash.items.any((item) => item.id == trashItemId)) {
      appTrash = appTrash.bump().copyWith(
            items: appTrash.items.where((item) => item.id != trashItemId).toList(),
          );
      await _persistAppTrash();
      return;
    }

    for (final entry in projectTrashes.entries.toList()) {
      if (!entry.value.items.any((item) => item.id == trashItemId)) continue;
      final next = entry.value.bump().copyWith(
            items: entry.value.items
                .where((item) => item.id != trashItemId)
                .toList(),
          );
      projectTrashes[entry.key] = next;
      if (entry.key == activeProjectId) {
        activeProjectTrash = next;
      }
      await _repository.saveProjectTrash(entry.key, next);
      notifyListeners();
      _syncService.schedulePush();
      return;
    }
  }

  Future<void> emptyTrash() async {
    activeProjectTrash = TrashBin.empty.bump();
    appTrash = TrashBin.empty.bump();
    labelTrash = const [];

    for (final entry in manifest?.projects ?? const <ProjectEntry>[]) {
      final empty = TrashBin.empty.bump();
      projectTrashes[entry.id] = empty;
      await _repository.saveProjectTrash(entry.id, empty);
    }

    await _repository.saveAppTrash(appTrash);
    await _persistLabelTrash();
    notifyListeners();
    _syncService.schedulePush();
  }

  Future<String?> _restoreLabel(TrashItem item) async {
    final label = item.labelPayload;
    if (label == null) return '数据损坏，无法还原';

    if (appSettings.customLabels.any((l) => l.key == label.key)) {
      return '标签已存在';
    }

    await saveAppSettings(
      appSettings.copyWith(
        customLabels: [...appSettings.customLabels, label],
      ),
    );
    labelTrash = labelTrash.where((i) => i.id != item.id).toList();
    await _persistLabelTrash();
    return null;
  }

  Future<String?> _restoreProject(TrashItem item) async {
    final payload = item.projectPayload;
    if (payload == null) return '数据损坏，无法还原';
    if (manifest?.findById(payload.entry.id) != null) {
      return '项目已存在，无法还原';
    }

    await _repository.saveBoard(payload.entry.id, payload.board);
    await _repository.saveProjectSettings(payload.entry.id, payload.settings);
    await _repository.saveProjectTrash(payload.entry.id, payload.projectTrash);

    manifest = manifest!.bump().copyWith(
          projects: [...manifest!.projects, payload.entry],
        );
    await _repository.saveManifest(manifest!);

    projectTrashes[payload.entry.id] = payload.projectTrash;
    appTrash = appTrash.bump().copyWith(
          items: appTrash.items.where((i) => i.id != item.id).toList(),
        );
    await _repository.saveAppTrash(appTrash);
    notifyListeners();
    _syncService.schedulePush();
    return null;
  }

  Future<String?> _restoreProjectItem(String projectId, TrashItem item) async {
    if (manifest?.findById(projectId) == null) {
      return '所属项目不存在，请先还原项目';
    }

    final isActive = projectId == activeProjectId;
    final targetBoard =
        isActive ? board! : await _repository.loadBoard(projectId);

    return switch (item.type) {
      TrashItemType.card =>
        _restoreCardToBoard(projectId, targetBoard, item, isActive),
      TrashItemType.column =>
        _restoreColumnToBoard(projectId, targetBoard, item, isActive),
      _ => '无法还原此类型',
    };
  }

  Future<String?> _restoreCardToBoard(
    String projectId,
    KanbanBoard targetBoard,
    TrashItem item,
    bool isActive,
  ) async {
    final card = item.cardPayload;
    if (card == null) return '数据损坏，无法还原';

    for (final col in targetBoard.columns) {
      if (col.cards.any((c) => c.id == card.id)) {
        return '卡片已存在，无法还原';
      }
    }

    var columns = [...targetBoard.columns];
    final columnId = item.columnId;
    final columnIndex =
        columnId == null ? -1 : columns.indexWhere((c) => c.id == columnId);

    if (columnIndex < 0) {
      columns.add(
        KanbanColumn(
          id: columnId ?? const Uuid().v4(),
          title: item.columnTitle ?? '已恢复的列',
          order: columns.length,
          cards: [card],
        ),
      );
    } else {
      final col = columns[columnIndex];
      columns[columnIndex] = col.copyWith(cards: [...col.cards, card]);
    }

    await _saveBoardForProject(
      projectId,
      _bump(targetBoard.copyWith(columns: columns)),
      isActive,
    );
    await _removeTrashItem(item);
    return null;
  }

  Future<String?> _restoreColumnToBoard(
    String projectId,
    KanbanBoard targetBoard,
    TrashItem item,
    bool isActive,
  ) async {
    final payload = item.columnPayload;
    if (payload == null) return '数据损坏，无法还原';

    var column = payload;
    var columns = [...targetBoard.columns];
    if (columns.any((c) => c.id == column.id)) {
      column = column.copyWith(
        id: const Uuid().v4(),
        order: columns.length,
      );
    }

    final insertAt = column.order.clamp(0, columns.length);
    columns.insert(insertAt, column);
    for (var i = 0; i < columns.length; i++) {
      columns[i] = columns[i].copyWith(order: i);
    }

    await _saveBoardForProject(
      projectId,
      _bump(targetBoard.copyWith(columns: columns)),
      isActive,
    );
    await _removeTrashItem(item);
    return null;
  }

  Future<void> _saveBoardForProject(
    String projectId,
    KanbanBoard next,
    bool isActive,
  ) async {
    await _repository.saveBoard(projectId, next);
    if (isActive) {
      board = next;
      await _updateManifestEntry(title: next.title);
    }
    notifyListeners();
    _syncService.schedulePush();
  }

  Future<void> _removeTrashItem(TrashItem item) async {
    final projectId = item.projectId;
    if (projectId == null) return;

    final bin = projectTrashes[projectId] ?? TrashBin.empty;
    final next = bin.bump().copyWith(
          items: bin.items.where((i) => i.id != item.id).toList(),
        );
    projectTrashes[projectId] = next;
    if (projectId == activeProjectId) {
      activeProjectTrash = next;
    }
    await _repository.saveProjectTrash(projectId, next);
    notifyListeners();
    _syncService.schedulePush();
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
        await _loadTrashState();
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
      await _loadTrashState();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _syncService.dispose();
    super.dispose();
  }
}
