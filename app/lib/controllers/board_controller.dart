import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../common/async_mutex.dart';
import '../features/attachments/attachment_missing.dart';
import '../features/attachments/attachment_refs.dart';
import '../features/attachments/attachment_store.dart';
import '../features/attachments/attachment_sync_adapter.dart';
import '../features/attachments/card_image_picker.dart';
import '../features/activity/activity_models.dart';
import '../features/automations/automations.dart';
import '../features/completed_auto_clear/completed_auto_clear.dart';
import '../features/import_export/backup_archive_service.dart';
import '../features/import_export/backup_coordinator.dart';
import '../features/import_export/backup_history_store.dart';
import '../features/mcp/kanban_mcp_host.dart';
import '../features/project/project_list_preferences.dart';
import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../features/project/project_theme.dart';
import '../features/quick_capture/quick_capture.dart';
import '../features/reminders/recurrence_service.dart';
import '../features/reminders/reminder_scheduler.dart';
import '../features/shared_content/shared_content.dart';
import '../features/statistics/statistics_service.dart';
import '../features/sync_conflict/sync_conflict.dart';
import '../features/templates/card_template.dart';
import '../features/templates/create_card_choice.dart';
import '../features/undo/undo_stack.dart';
import '../features/views/views.dart';
import '../models/kanban_models.dart';
import '../features/kanban/column_card_preferences.dart';
import '../features/kanban/kanban_labels.dart';
import '../features/kanban/move_to_rework_on_new_feedback.dart';
import '../features/kanban/transfer_card.dart';
import '../features/trash/trash_models.dart';
import '../settings/app_settings.dart';
import '../storage/board_storage.dart';
import '../webdav_sync/webdav_config.dart';
import '../webdav_sync/webdav_sync_service.dart';

enum CardConflictResolution { keepPrimary, keepOther }

final Object _projectMutationScopeKey = Object();

/// 设置页启用提醒后的结果，用于给用户准确反馈。
enum NotificationPermissionResult {
  enabled,
  denied,
  openedSystemSettings,
}

class BoardController extends ChangeNotifier {
  BoardController._({
    required BoardRepository repository,
    required WebDavSyncService syncService,
    required BackupHistoryStore backupHistoryStore,
  })  : _repository = repository,
        _syncService = syncService {
    _backupHistorySupported = backupHistoryStore.isSupported;
    _backupCoordinator = BackupCoordinator(
      localStore: backupHistoryStore,
      createArchive: createBackupArchive,
      writeRemote: _syncService.writeBackupSnapshot,
      listRemote: _syncService.listRemoteBackupSnapshots,
      pruneRemote: _syncService.deleteRemoteBackupsOlderThan,
    );
  }

  final BoardRepository _repository;
  final WebDavSyncService _syncService;
  late final bool _backupHistorySupported;
  late final BackupCoordinator _backupCoordinator;
  final ReminderScheduler _reminderScheduler = ReminderScheduler();
  final UndoStack _undoStack = UndoStack();
  static const RecurrenceService _recurrenceService = RecurrenceService();
  static const AutomationEngine _automationEngine = AutomationEngine();
  bool _applyingAutomation = false;

  /// 当前突变来源（MCP 经 [runWithActivitySource] 置位）。
  ActivitySource _mutationOrigin = ActivitySource.user;

  /// 串行化看板/清单突变，避免 MCP runOnProject 与 UI 写交错。
  final AsyncMutex _boardMutationMutex = AsyncMutex();

  /// 已完成自动清空：上次扫描时间（进程内节流）
  DateTime? _lastCompletedAutoClearAt;
  bool _completedAutoClearRunning = false;

  KanbanBoard? _uiBoard;
  KanbanBoard? get board => _projectMutationScope?.board ?? _uiBoard;
  set board(KanbanBoard? value) {
    final scope = _projectMutationScope;
    if (scope != null) {
      scope.board = value;
    } else {
      _uiBoard = value;
    }
  }

  ProjectsManifest? manifest;
  String? _uiActiveProjectId;
  String? get activeProjectId =>
      _projectMutationScope?.projectId ?? _uiActiveProjectId;
  set activeProjectId(String? value) {
    final scope = _projectMutationScope;
    if (scope != null) {
      if (value != scope.projectId) {
        throw StateError('项目数据作用域内不能切换项目');
      }
      return;
    }
    _uiActiveProjectId = value;
  }

  ProjectSettings _uiProjectSettings = const ProjectSettings();
  ProjectSettings get projectSettings =>
      _projectMutationScope?.settings ?? _uiProjectSettings;
  set projectSettings(ProjectSettings value) {
    final scope = _projectMutationScope;
    if (scope != null) {
      scope.settings = value;
    } else {
      _uiProjectSettings = value;
    }
  }
  /// 各项目 themeId 缓存（供项目切换菜单等展示；权威数据仍在 settings.json）
  Map<String, String> projectThemeIds = {};
  SharedContent sharedContent = SharedContent.empty;
  WebDavConfig webDavConfig = WebDavConfig.empty;
  AppSettings appSettings = AppSettings.platformDefault();
  late final KanbanMcpHost mcpHost = KanbanMcpHost(this);
  TrashBin _uiActiveProjectTrash = TrashBin.empty;
  TrashBin get activeProjectTrash =>
      _projectMutationScope?.trash ?? _uiActiveProjectTrash;
  set activeProjectTrash(TrashBin value) {
    final scope = _projectMutationScope;
    if (scope != null) {
      scope.trash = value;
    } else {
      _uiActiveProjectTrash = value;
    }
  }
  TrashBin appTrash = TrashBin.empty;
  Map<String, TrashBin> projectTrashes = {};
  List<TrashItem> labelTrash = const [];
  Set<String> missingAttachmentIds = {};
  bool isLoading = true;
  String? errorMessage;

  SyncStatus get syncStatus => _syncService.status;
  String? get syncError => _syncService.lastError;
  String? get attachmentSyncWarning => _syncService.attachmentSyncWarning;
  DateTime? get lastSyncedAt => _syncService.lastSyncedAt;
  SyncProgress? get syncProgress => _syncService.progress;
  int get pendingSyncUploadCount => _syncService.pendingUploadCount;
  Stream<SyncStatus> get syncStatusStream => _syncService.statusStream;
  Stream<SyncProgress?> get syncProgressStream => _syncService.progressStream;
  bool get canUndo => _undoStack.canUndo;
  bool get canRedo => _undoStack.canRedo;
  String? get undoLabel => _undoStack.nextUndoLabel;
  String? get redoLabel => _undoStack.nextRedoLabel;
  bool get backupHistorySupported => _backupHistorySupported;

  /// 界面当前项目 id；后台项目数据作用域不会改变此值。
  String? get uiActiveProjectId => _uiActiveProjectId;

  _ProjectMutationScope? get _projectMutationScope {
    final value = Zone.current[_projectMutationScopeKey];
    if (value is _ProjectMutationScope && value.isActive) return value;
    return null;
  }

  bool get _mutatingForeignProject => _projectMutationScope != null;

  Future<void> initializeReminders({bool requestPermission = false}) async {
    try {
      await _reminderScheduler.initialize();
      if (requestPermission) {
        await _requestNotificationPermissionAndPersist();
      }
      await _rescheduleReminders();
    } catch (error) {
      debugPrint('初始化任务提醒失败：$error');
    }
  }

  /// 安装后首次进入界面时申请通知权限（需 Activity 就绪）。
  Future<bool> ensureNotificationPermissionOnFirstLaunch() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    if (appSettings.hasRequestedNotificationPermission) {
      return _reminderScheduler.areNotificationsEnabled();
    }
    return _requestNotificationPermissionAndPersist();
  }

  /// 设置页：已授权则重新调度；未授权则弹窗；永久拒绝则打开系统设置。
  Future<NotificationPermissionResult> enableRemindersFromSettings() async {
    try {
      await _reminderScheduler.initialize();
      final alreadyEnabled =
          await _reminderScheduler.areNotificationsEnabled();
      if (alreadyEnabled) {
        await _rescheduleReminders();
        return NotificationPermissionResult.enabled;
      }

      final granted = await _requestNotificationPermissionAndPersist();
      if (granted) {
        await _rescheduleReminders();
        return NotificationPermissionResult.enabled;
      }

      // 再请求仍未授权，多半是永久拒绝，引导系统设置。
      final opened =
          await _reminderScheduler.openSystemNotificationSettings();
      return opened
          ? NotificationPermissionResult.openedSystemSettings
          : NotificationPermissionResult.denied;
    } catch (error) {
      debugPrint('启用任务提醒失败：$error');
      return NotificationPermissionResult.denied;
    }
  }

  Future<bool> notificationsEnabled() =>
      _reminderScheduler.areNotificationsEnabled();

  Future<bool> _requestNotificationPermissionAndPersist() async {
    final granted = await _reminderScheduler.requestPermission();
    if (!appSettings.hasRequestedNotificationPermission) {
      await saveAppSettings(
        appSettings.copyWith(hasRequestedNotificationPermission: true),
      );
    }
    return granted;
  }

  Future<void> _rescheduleReminders() async {
    final workspace = await _loadWorkspaceSnapshot();
    await _reminderScheduler.rescheduleAll(workspace.boards);
  }

  /// 调度前若通知未开，再申请一次（用户正在设置提醒时）。
  Future<void> _scheduleCardReminder({
    required String projectId,
    required String columnId,
    required KanbanCard card,
  }) async {
    if (card.reminderAt == null || card.completed) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final enabled = await _reminderScheduler.areNotificationsEnabled();
      if (!enabled) {
        await _requestNotificationPermissionAndPersist();
      }
    }
    await _reminderScheduler.schedule(
      projectId: projectId,
      columnId: columnId,
      card: card,
    );
  }

  Future<bool> undoLastAction() async {
    return _withBoardMutation(() async {
      final undone = await _undoStack.undo();
      if (undone) notifyListeners();
      return undone;
    });
  }

  Future<bool> redoLastAction() async {
    return _withBoardMutation(() async {
      final redone = await _undoStack.redo();
      if (redone) notifyListeners();
      return redone;
    });
  }

  Future<Uint8List> createBackupArchive() async {
    // 短持锁捕获工作区；附件二进制读取放锁外，避免长时间阻塞冲突解决等 UI 写操作。
    final workspace = await _loadWorkspaceSnapshot();
    final labels = labelTrash;
    final attachments = <String, Uint8List>{};
    final store = attachmentStore;
    if (store != null) {
      for (final project in workspace.manifest.projects) {
        for (final attachmentId
            in await store.listLocalAttachmentIds(project.id)) {
          final source = await store.readBytes(
            projectId: project.id,
            attachmentId: attachmentId,
            thumb: false,
          );
          if (source != null) {
            attachments['attachments/${project.id}/$attachmentId'] = source;
          }
          final thumb = await store.readBytes(
            projectId: project.id,
            attachmentId: attachmentId,
            thumb: true,
          );
          if (thumb != null) {
            attachments['attachments/${project.id}/thumbs/$attachmentId'] =
                thumb;
          }
        }
      }
    }
    return const BackupArchiveService().encode(
      BackupPackage(
        workspace: workspace,
        attachments: attachments,
        labelTrash: labels,
      ),
    );
  }

  Future<void> restoreBackupArchive(Uint8List bytes) async {
    return _backupCoordinator.runExclusive(() async {
      final service = const BackupArchiveService();
      final package = service.decode(bytes);
      // 安全备份在看板锁外生成，避免读附件时卡住其它突变。
      final safetyBytes = await createBackupArchive();
      if (_backupHistorySupported) {
        final safetySnapshot =
            await _backupCoordinator.storeArchiveNow(safetyBytes);
        await _repository.savePendingRestoreBackupId(safetySnapshot.id);
      }
      try {
        await _withBoardMutation(() async {
          await _applyBackupPackage(package);
          if (_backupHistorySupported) {
            await _repository.clearPendingRestoreBackupId();
          }
          notifyListeners();
          _markWorkspaceChanged();
        });
      } catch (error, stackTrace) {
        try {
          await _withBoardMutation(() async {
            await _applyBackupPackage(service.decode(safetyBytes));
            if (_backupHistorySupported) {
              await _repository.clearPendingRestoreBackupId();
            }
            notifyListeners();
            _markWorkspaceChanged();
          });
        } catch (rollbackError) {
          throw StateError(
            '恢复失败且自动回滚失败：$error；回滚错误：$rollbackError',
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  Future<void> _applyBackupPackage(BackupPackage package) async {
    final previousProjectIds = {
      for (final project in manifest?.projects ?? const <ProjectEntry>[])
        project.id,
    };
    await _applyWorkspaceSnapshot(package.workspace);
    labelTrash = package.labelTrash;
    await _repository.saveLabelTrash(labelTrash);
    final store = attachmentStore;
    if (store == null) return;
    for (final entry in package.attachments.entries) {
      final segments = entry.key.split('/');
      if (segments.length < 3) continue;
      final isThumb = segments.length >= 4 && segments[2] == 'thumbs';
      final attachmentId = isThumb ? segments[3] : segments[2];
      await store.writeBytes(
        projectId: segments[1],
        attachmentId: attachmentId,
        bytes: entry.value,
        thumb: isThumb,
      );
    }
    final restoredProjectIds = {
      for (final project in package.workspace.manifest.projects) project.id,
    };
    for (final projectId in {...previousProjectIds, ...restoredProjectIds}) {
      final keepIds = <String>{
        for (final path in package.attachments.keys)
          if (path.startsWith('attachments/$projectId/') &&
              !path.contains('/thumbs/'))
            path.split('/').last,
      };
      await store.deleteOrphans(projectId: projectId, keepIds: keepIds);
    }
    await refreshMissingAttachments();
  }

  Future<BackupSnapshotInfo> createTimePointBackup() =>
      _backupCoordinator.createBackupNow();

  Future<List<BackupSnapshotInfo>> listLocalTimePointBackups() =>
      _backupCoordinator.listLocalBackups();

  Future<List<BackupSnapshotInfo>> listRemoteTimePointBackups() =>
      _syncService.listRemoteBackupSnapshots();

  Future<void> restoreTimePointBackup(
    String id, {
    bool remote = false,
  }) async {
    final bytes = remote
        ? await _syncService.readRemoteBackupSnapshot(id)
        : await _backupCoordinator.readLocalBackup(id);
    if (bytes == null) throw StateError('备份不存在或无法读取');
    await restoreBackupArchive(bytes);
  }

  Future<void> deleteLocalTimePointBackup(String id) =>
      _backupCoordinator.deleteLocalBackup(id);

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

  /// 读取某项目的主题 id；当前项目以内存中的设置为准
  String themeIdForProject(String projectId) {
    if (projectId == activeProjectId) return projectSettings.themeId;
    return projectThemeIds[projectId] ?? '';
  }

  Future<void> _refreshProjectThemeIds() async {
    final entries = manifest?.projects ?? const <ProjectEntry>[];
    if (entries.isEmpty) {
      projectThemeIds = {};
      return;
    }
    final next = <String, String>{};
    for (final entry in entries) {
      if (entry.id == activeProjectId) {
        next[entry.id] = projectSettings.themeId;
        continue;
      }
      final settings = await _repository.loadProjectSettings(entry.id);
      next[entry.id] = settings.themeId;
    }
    projectThemeIds = next;
  }

  void _setProjectThemeIdsFrom(Map<String, ProjectSettings> settings) {
    projectThemeIds = {
      for (final entry in settings.entries) entry.key: entry.value.themeId,
    };
  }

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

  AttachmentStore? get attachmentStore => _repository.attachmentStore;

  Future<Uint8List?> readAttachmentBytes(
    String attachmentId, {
    bool thumb = true,
    String? projectId,
  }) async {
    final store = attachmentStore;
    final pid = projectId ?? activeProjectId;
    if (store == null || pid == null) return null;
    return store.readBytes(
      projectId: pid,
      attachmentId: attachmentId,
      thumb: thumb,
    );
  }

  bool isAttachmentMissing(String attachmentId) =>
      missingAttachmentIds.contains(attachmentId);

  int missingAttachmentsForCard(KanbanCard card) =>
      countMissingAttachmentsForCard(card, missingAttachmentIds);

  Future<void> refreshMissingAttachments({String? projectId}) async {
    final pid = projectId ?? activeProjectId;
    final store = attachmentStore;
    if (store == null || pid == null || board == null) {
      missingAttachmentIds = {};
      notifyListeners();
      return;
    }

    final trash = projectTrashes[pid] ?? activeProjectTrash;
    missingAttachmentIds = await findMissingAttachmentIds(
      store: store,
      projectId: pid,
      board: board!,
      trash: trash,
      settings: projectId == null || projectId == activeProjectId
          ? projectSettings
          : null,
    );
    notifyListeners();
  }

  ProjectEntry? get activeProject {
    if (activeProjectId == null || manifest == null) return null;
    return manifest!.findById(activeProjectId!);
  }

  List<SavedView> get savedViews => sharedContent.savedViews;
  List<CardTemplate> get cardTemplates => sharedContent.cardTemplates;
  List<ActivityEvent> get activeProjectActivity =>
      activityForProject(activeProjectId);

  /// 按项目读取活动历史（不切换当前项目）。
  List<ActivityEvent> activityForProject(String? projectId) {
    final events = [
      ...(sharedContent.activityByProject[projectId]?.events ??
          const <ActivityEvent>[]),
    ];
    events.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return events;
  }

  /// 只读加载某项目设置快照（不切换当前项目）。
  Future<ProjectSettings?> loadProjectSettingsSnapshot(String projectId) async {
    return _withBoardMutation(() async {
      if (projectId == activeProjectId) return projectSettings;
      if (manifest?.findById(projectId) == null) return null;
      return _repository.loadProjectSettings(projectId);
    });
  }

  Future<List<CardReference>> loadAllCardReferences() async {
    final workspace = await _loadWorkspaceSnapshot();
    return buildCardReferences(
      manifest: workspace.manifest,
      boards: workspace.boards,
      customLabels: appSettings.customLabels,
    );
  }

  Future<KanbanStatistics> loadStatistics() async {
    final workspace = await _loadWorkspaceSnapshot();
    return const StatisticsService().calculate(workspace.boards);
  }

  Future<void> saveView({
    String? id,
    required String name,
    required FilterSpec filter,
  }) async {
    return _withBoardMutation(() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final viewId = id ?? const Uuid().v4();
    final existing =
        sharedContent.savedViews.where((view) => view.id == viewId).firstOrNull;
    final view = SavedView(
      id: viewId,
      name: name.trim(),
      filter: filter,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _persistSharedContent(
      sharedContent.copyWith(
        savedViews: [
          for (final item in sharedContent.savedViews)
            if (item.id != viewId) item,
          view,
        ],
      ),
    );
      });
  }

  Future<void> deleteSavedView(String id) async {
    return _withBoardMutation(() async {
    await _persistSharedContent(
      sharedContent.copyWith(
        savedViews:
            sharedContent.savedViews.where((view) => view.id != id).toList(),
      ),
    );
      });
  }

  Future<String> saveCardAsTemplate({
    required KanbanCard card,
    required String name,
  }) async {
    return _withBoardMutation(() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final template = CardTemplate.fromCard(
      id: const Uuid().v4(),
      name: name.trim(),
      card: card,
      updatedAt: now,
    );
    await _persistSharedContent(
      sharedContent.copyWith(
        cardTemplates: [...sharedContent.cardTemplates, template],
      ),
    );
    return template.id;
      });
  }

  Future<String?> createCardFromTemplate({
    required String templateId,
    required String columnId,
  }) async {
    return _withBoardMutation(() async {
    final template = sharedContent.cardTemplates
        .where((item) => item.id == templateId)
        .firstOrNull;
    if (template == null || board == null) return null;
    final cardId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final card = template.createCard(
      cardId: cardId,
      createdAt: now,
      checklistIds: [
        for (var i = 0; i < template.checklist.length; i++) const Uuid().v4(),
      ],
    );
    final columns = board!.columns.map((column) {
      if (column.id != columnId) return column;
      return column.copyWith(
        cards: [
          ...column.cards,
          card.copyWith(order: column.cards.length),
        ],
      );
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
    String? trashId;
    _pushUndo(
      '新建「${card.title}」',
      () async {
        trashId = await deleteCard(columnId, cardId);
      },
      redo: () async {
        final id = trashId;
        if (id == null) return;
        final error = await restoreTrashItem(id);
        if (error != null) throw StateError(error);
      },
    );
    await _recordActivity(
      entityId: cardId,
      entityTitle: card.title,
      action: ActivityAction.created,
    );
    return cardId;
      });
  }

  Future<void> deleteCardTemplate(String id) async {
    return _withBoardMutation(() async {
    await _persistSharedContent(
      sharedContent.copyWith(
        cardTemplates: removeCardTemplateById(sharedContent.cardTemplates, id),
      ),
    );
      });
  }

  Future<String?> quickCapture(QuickCaptureDraft draft) async {
    return _withBoardMutation(() async {
    if (board == null || draft.title.trim().isEmpty) return null;
    final desiredColumn = draft.columnName?.trim();
    final column = board!.columns.cast<KanbanColumn?>().firstWhere(
          (item) =>
              desiredColumn != null &&
              item!.title.toLowerCase() == desiredColumn.toLowerCase(),
          orElse: () => board!.columns.cast<KanbanColumn?>().firstWhere(
                (item) => item!.id == 'todo',
                orElse: () =>
                    board!.columns.isEmpty ? null : board!.columns.first,
              ),
        );
    if (column == null) return null;

    final labelKeys = <String>[];
    for (final name in draft.labels) {
      final existing = appSettings.customLabels.cast<KanbanLabel?>().firstWhere(
            (label) => label!.name.toLowerCase() == name.toLowerCase(),
            orElse: () => null,
          );
      if (existing != null) {
        labelKeys.add(existing.key);
      } else {
        labelKeys.add(
          await addCustomLabel(
            name,
            projectThemeForId(projectSettings.themeId)
                .defaultLabelColor
                .toARGB32(),
          ),
        );
      }
    }

    final priority = switch (draft.priority) {
      QuickCapturePriority.low => CardPriority.low,
      QuickCapturePriority.medium => CardPriority.medium,
      QuickCapturePriority.high => CardPriority.high,
      null => CardPriority.none,
    };
    return addCard(
      column.id,
      draft.title.trim(),
      dueDate: draft.dueDate?.millisecondsSinceEpoch,
      priority: priority,
      labels: labelKeys,
    );
      });
  }

  int get unresolvedConflictCount {
    var n = 0;
    if (board != null) {
      for (final col in board!.columns) {
        for (final card in col.cards) {
          if (card.hasConflict) n++;
        }
      }
      if (board!.conflictTitle != null) n++;
    }
    if (projectSettings.hasConflict) n++;
    if (manifest != null) {
      for (final p in manifest!.projects) {
        if (p.hasConflict) n++;
      }
    }
    return n;
  }

  static Future<BoardController> create() async {
    final prefs = await SharedPreferences.getInstance();
    return createForTest(prefs: prefs, startBackupScheduler: true);
  }

  /// 测试用：可注入 prefs / 存储根目录，便于隔离。
  @visibleForTesting
  static Future<BoardController> createForTest({
    required SharedPreferences prefs,
    BoardStorage? storage,
    BackupHistoryStore? backupHistoryStore,
    bool startBackupScheduler = false,
  }) async {
    final repository = BoardRepository(prefs, storage);
    final attachmentSync = AttachmentSyncAdapter(repository.attachmentStore);
    late BoardController controller;
    final syncService = WebDavSyncService(
      loadConfig: () async => controller.webDavConfig,
      loadWorkspace: () async => controller._loadWorkspaceSnapshot(),
      saveWorkspace: (workspace) async =>
          controller._applyWorkspaceSnapshot(workspace),
      syncBaseStore: SyncBaseStore(prefs),
      attachmentSync: attachmentSync,
      runWorkspaceTransaction: <T>(action) =>
          controller._withBoardMutation(action),
    );
    controller = BoardController._(
      repository: repository,
      syncService: syncService,
      backupHistoryStore: backupHistoryStore ?? BackupHistoryStore(),
    );
    await controller._init();
    if (startBackupScheduler && controller._backupHistorySupported) {
      controller._backupCoordinator.start();
    }
    return controller;
  }

  @override
  void notifyListeners() {
    final scope = _projectMutationScope;
    if (scope != null) {
      scope.pendingNotify = true;
      return;
    }
    super.notifyListeners();
  }


  /// 看板突变临界区：同一异步调用链可重入，UI、MCP 与同步之间严格串行。
  Future<T> _withBoardMutation<T>(Future<T> Function() action) =>
      _boardMutationMutex.guard(action);

  void _markWorkspaceChanged() {
    _backupCoordinator.markChanged();
    // 防抖 Timer 不继承当前 mutation/project Zone，触发时必须重新排队。
    Zone.root.run(_syncService.schedulePush);
  }

  /// 以指定活动来源执行操作（供 MCP 等外部写入标注来源）。
  Future<T> runWithActivitySource<T>(
    ActivitySource source,
    Future<T> Function() action,
  ) async {
    final previous = _mutationOrigin;
    _mutationOrigin = source;
    try {
      return await action();
    } finally {
      _mutationOrigin = previous;
    }
  }

  ActivitySource get _currentActivitySource {
    if (_applyingAutomation) return ActivitySource.automation;
    return _mutationOrigin;
  }

  /// 推入撤销/重做项；自动化不入栈。跨项目 MCP 写入时用 [runOnProject] 包一层以便恢复。
  void _pushUndo(
    String label,
    UndoCallback undo, {
    required UndoCallback redo,
  }) {
    if (_applyingAutomation) return;
    final source = _mutationOrigin;
    final displayLabel =
        source == ActivitySource.mcp ? 'MCP：$label' : label;
    final scopedProjectId =
        _mutatingForeignProject ? activeProjectId : null;
    if (scopedProjectId != null) {
      _undoStack.push(
        UndoEntry(
          label: displayLabel,
          undo: () => runOnProject(scopedProjectId, undo),
          redo: () => runOnProject(scopedProjectId, redo),
        ),
      );
      return;
    }
    _undoStack.push(
      UndoEntry(label: displayLabel, undo: undo, redo: redo),
    );
  }

  /// 在指定项目上下文中执行操作：不修改已持久化的 active 项目，也不把 UI 切走。
  ///
  /// 若 [projectId] 即为当前项目，直接执行 [action]。
  /// 对外项目：在独立的异步数据作用域中加载和修改，不改变 UI 当前状态。
  Future<T> runOnProject<T>(
    String projectId,
    Future<T> Function() action,
  ) async {
    return _withBoardMutation(() async {
      if (manifest?.findById(projectId) == null) {
        throw StateError('项目不存在：$projectId');
      }
      if (projectId == activeProjectId) {
        return action();
      }
      if (_projectMutationScope != null) {
        throw StateError('不可嵌套 runOnProject');
      }

      final scope = _ProjectMutationScope(
        projectId: projectId,
        board: await _repository.loadBoard(projectId),
        settings: await _repository.loadProjectSettings(projectId),
        trash: projectTrashes[projectId] ?? TrashBin.empty,
      );

      try {
        return await runZoned(
          () async {
            await _ensureReworkColumnPersisted();
            return action();
          },
          zoneValues: {_projectMutationScopeKey: scope},
        );
      } finally {
        scope.isActive = false;
        projectTrashes[projectId] = scope.trash;
        projectThemeIds[projectId] = scope.settings.themeId;
        if (scope.pendingNotify) {
          notifyListeners();
        }
      }
    });
  }

  Future<ProjectWorkspaceSnapshot> _loadWorkspaceSnapshot() async {
    return _withBoardMutation(() async {
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
        sharedContent: await _repository.loadSharedContent(),
      );
    });
  }

  Future<void> _applyWorkspaceSnapshot(
    ProjectWorkspaceSnapshot workspace,
  ) async {
    return _withBoardMutation(() async {
      final previousProjectIds = {
        for (final project in manifest?.projects ?? const <ProjectEntry>[])
          project.id,
      };
      final nextProjectIds = {
        for (final project in workspace.manifest.projects) project.id,
      };
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
      await _repository.saveSharedContent(workspace.sharedContent);
      for (final projectId in previousProjectIds.difference(nextProjectIds)) {
        await _repository.storage.deleteProjectData(projectId);
      }
      // 清单最后提交，避免它提前指向尚未完整写入的项目数据。
      await _repository.saveManifest(workspace.manifest);

      manifest = workspace.manifest;
      projectTrashes = Map<String, TrashBin>.from(workspace.projectTrash);
      appTrash = workspace.appTrash;
      sharedContent = workspace.sharedContent;
      _setProjectThemeIdsFrom(workspace.settings);
      await _mirrorSharedLabelsToLocalPreferences();
      final currentId = activeProjectId;
      if (currentId != null && workspace.manifest.findById(currentId) != null) {
        board = workspace.boards[currentId];
        projectSettings =
            workspace.settings[currentId] ?? const ProjectSettings();
        activeProjectTrash = workspace.projectTrash[currentId] ?? TrashBin.empty;
      } else if (workspace.manifest.projects.isNotEmpty) {
        final first = workspace.manifest.projects.first;
        activeProjectId = first.id;
        await _repository.saveActiveProjectId(first.id);
        board = workspace.boards[first.id];
        projectSettings = workspace.settings[first.id] ?? const ProjectSettings();
        activeProjectTrash = workspace.projectTrash[first.id] ?? TrashBin.empty;
      }
      _backupCoordinator.markChanged();
      await refreshMissingAttachments();
    });
  }

  Future<void> _loadTrashState() async {
    appTrash = await _repository.loadAppTrash();
    labelTrash = _repository.loadLabelTrash();
    projectTrashes = {};
    if (manifest != null) {
      for (final entry in manifest!.projects) {
        projectTrashes[entry.id] = await _repository.loadProjectTrash(entry.id);
      }
    }
    if (activeProjectId != null) {
      activeProjectTrash = projectTrashes[activeProjectId!] ?? TrashBin.empty;
    } else {
      activeProjectTrash = TrashBin.empty;
    }
  }

  Future<void> _persistActiveProjectTrash() async {
    if (activeProjectId == null) return;
    projectTrashes[activeProjectId!] = activeProjectTrash;
    await _repository.saveProjectTrash(activeProjectId!, activeProjectTrash);
    notifyListeners();
    _markWorkspaceChanged();
  }

  Future<void> _persistAppTrash() async {
    await _repository.saveAppTrash(appTrash);
    notifyListeners();
    _markWorkspaceChanged();
  }

  Future<void> _persistLabelTrash() async {
    await _repository.saveLabelTrash(labelTrash);
    _backupCoordinator.markChanged();
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
      await _recoverInterruptedRestoreIfNeeded();
      manifest = await _repository.loadManifest();
      activeProjectId = _repository.loadActiveProjectId();

      if (activeProjectId == null ||
          manifest!.findById(activeProjectId!) == null) {
        activeProjectId = manifest!.projects.first.id;
        await _repository.saveActiveProjectId(activeProjectId!);
      }

      board = await _repository.loadBoard(activeProjectId!);
      projectSettings = await _repository.loadProjectSettings(activeProjectId!);
      await _ensureReworkColumnPersisted();
      await _refreshProjectThemeIds();
      await _loadTrashState();
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }

    unawaited(runOverdueAutomations());
    unawaited(_rescheduleReminders());
    unawaited(purgeExpiredCompletedCards());

    _syncService.statusStream.listen((status) {
      if (status == SyncStatus.success || status == SyncStatus.error) {
        unawaited(refreshMissingAttachments());
      }
      notifyListeners();
    });
    _syncService.progressStream.listen((_) {
      notifyListeners();
    });
    _syncService.pendingUploadCountStream.listen((_) {
      notifyListeners();
    });
    unawaited(_syncService.refreshPendingUploadCount());

    if (webDavConfig.enabled && webDavConfig.isConfigured) {
      if (webDavConfig.autoPull) {
        _syncService.startPolling();
        unawaited(_syncInBackground());
      } else {
        _syncService.stopPolling();
      }
    }

    unawaited(_syncMcpHost());
  }

  Future<void> _recoverInterruptedRestoreIfNeeded() async {
    final backupId = _repository.loadPendingRestoreBackupId();
    if (backupId == null) return;
    final bytes = await _backupCoordinator.readLocalBackup(backupId);
    if (bytes == null) {
      throw StateError('检测到未完成恢复，但安全备份不存在：$backupId');
    }
    final package = const BackupArchiveService().decode(bytes);
    await _applyBackupPackage(package);
    await _repository.clearPendingRestoreBackupId();
  }

  Future<void> _syncMcpHost() async {
    await mcpHost.syncWithSettings(
      enabled: appSettings.mcpEnabled,
      port: appSettings.mcpPort,
    );
  }

  /// 只读加载某项目看板快照（不切换当前项目）。
  Future<KanbanBoard?> loadBoardSnapshot(String projectId) async {
    return _withBoardMutation(() async {
      if (projectId == activeProjectId) return board;
      if (manifest?.findById(projectId) == null) return null;
      if (!await _repository.storage.hasProjectBoard(projectId)) return null;
      return _repository.loadBoard(projectId);
    });
  }

  Future<void> _syncInBackground() async {
    try {
      // 网络阶段不持看板突变锁；服务内部仅在捕获/落盘时短持锁。
      await _syncService.pullAndMerge();
      await _reloadUiAfterSync();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _reloadUiAfterSync() {
    return _withBoardMutation(() async {
      manifest = await _repository.loadManifest();
      if (activeProjectId != null) {
        board = await _repository.loadBoard(activeProjectId!);
        projectSettings =
            await _repository.loadProjectSettings(activeProjectId!);
        await _ensureReworkColumnPersisted();
        sharedContent = await _repository.loadSharedContent();
        await _initializeSharedLabels();
        await _refreshProjectThemeIds();
        await _loadTrashState();
      }
      await refreshMissingAttachments();
      notifyListeners();
    });
  }

  Future<void> _persistAndSync(KanbanBoard next) async {
    return _withBoardMutation(() async {
      // 以看板 id 为落盘主键，避免与 active 短暂不一致时写错项目文件。
      final projectId = next.id.isNotEmpty ? next.id : activeProjectId;
      if (projectId == null) return;
      if (activeProjectId == projectId) {
        board = next;
      }
      await _repository.saveBoard(projectId, next);
      if (activeProjectId == projectId) {
        await _updateManifestEntry(title: next.title);
      }
      notifyListeners();
      _markWorkspaceChanged();
    });
  }

  Future<void> _persistSharedContent(SharedContent next) async {
    return _withBoardMutation(() async {
      sharedContent = next.bump();
      await _repository.saveSharedContent(sharedContent);
      await _mirrorSharedLabelsToLocalPreferences();
      notifyListeners();
      _markWorkspaceChanged();
    });
  }

  Future<void> _recordActivity({
    required String entityId,
    required String entityTitle,
    required ActivityAction action,
    String entityType = 'card',
    Map<String, String> details = const {},
    ActivitySource? source,
  }) async {
    final projectId = activeProjectId;
    if (projectId == null) return;
    final resolvedSource = source ?? _currentActivitySource;
    final logs = Map<String, ActivityLog>.from(sharedContent.activityByProject);
    final current = logs[projectId] ?? const ActivityLog();
    logs[projectId] = current.add(
      ActivityEvent(
        id: const Uuid().v4(),
        projectId: projectId,
        entityType: entityType,
        entityId: entityId,
        entityTitle: entityTitle,
        action: action,
        occurredAt: DateTime.now().millisecondsSinceEpoch,
        source: resolvedSource,
        details: details,
      ),
    );
    await _persistSharedContent(
      sharedContent.copyWith(activityByProject: logs),
    );
  }

  Future<void> _initializeSharedLabels() async {
    if (sharedContent.isUninitialized && appSettings.customLabels.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _persistSharedContent(
        sharedContent.copyWith(
          labels: [
            for (final label in appSettings.customLabels)
              SharedLabel(
                id: label.key,
                name: label.name,
                colorValue: label.colorValue,
                updatedAt: now,
              ),
          ],
        ),
      );
      return;
    }
    await _mirrorSharedLabelsToLocalPreferences();
  }

  Future<void> _mirrorSharedLabelsToLocalPreferences() async {
    if (sharedContent.isUninitialized) return;
    final labels = [
      for (final label in sharedContent.labels)
        KanbanLabel(
          key: label.id,
          name: label.name,
          color: Color(label.colorValue),
        ),
    ];
    appSettings = appSettings.copyWith(customLabels: labels);
    await _repository.saveAppSettings(appSettings);
  }

  Future<void> _persistProjectSettings(ProjectSettings next) async {
    return _withBoardMutation(() async {
      if (activeProjectId == null) return;
      projectSettings = next;
      projectThemeIds[activeProjectId!] = next.themeId;
      await _repository.saveProjectSettings(activeProjectId!, next);
      notifyListeners();
      _markWorkspaceChanged();
    });
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
      resolveColumnCardPreferences(
        stored: projectSettings.columnPreferences[columnId],
        isDoneColumn: isDoneColumn(columnId),
      );

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
    return _withBoardMutation(() async {
    final current = columnPreferencesFor(columnId);
    if (current.sortMode == mode) return;
    await _saveColumnPreferences(
      columnId,
      current.copyWith(sortMode: mode),
    );
      });
  }

  Future<void> toggleCardPin(String columnId, String cardId) async {
    return _withBoardMutation(() async {
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
    await _saveColumnPreferences(
        columnId, prefs.copyWith(pinnedCardIds: pinned));
      });
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
    return findDoneColumn(
      current,
      doneColumnName: projectSettings.doneColumnName,
    );
  }

  /// 是否为当前项目设置中的已完成列（各项目可配置不同列名）。
  bool isDoneColumn(String columnId) {
    final current = board;
    if (current == null) return false;
    return _findDoneColumn(current)?.id == columnId;
  }

  Future<void> switchProject(String projectId) async {
    return _withBoardMutation(() async {
    if (manifest?.findById(projectId) == null) return;
    if (projectId == activeProjectId) return;

    activeProjectId = projectId;
    await _repository.saveActiveProjectId(projectId);
    board = await _repository.loadBoard(projectId);
    projectSettings = await _repository.loadProjectSettings(projectId);
    await _ensureReworkColumnPersisted();
    projectThemeIds[projectId] = projectSettings.themeId;
    activeProjectTrash = projectTrashes[projectId] ?? TrashBin.empty;
    await _recordProjectUsed(projectId);
    notifyListeners();
      });
  }

  Future<void> createProject(String title) async {
    return _withBoardMutation(() async {
    final projectId = await createProjectData(title);
    await switchProject(projectId);
      });
  }

  /// 创建项目数据但不改变界面当前项目，供 MCP 等后台调用。
  Future<String> createProjectData(String title) async {
    return _withBoardMutation(() async {
      final projectId = await _repository.createProject(title);
      manifest = await _repository.loadManifest();
      projectTrashes[projectId] = TrashBin.empty;
      projectThemeIds[projectId] = '';
      notifyListeners();
      _markWorkspaceChanged();
      return projectId;
    });
  }

  Future<void> renameActiveProject(String title) async {
    final projectId = activeProjectId;
    if (projectId == null) return;
    await renameProject(projectId, title);
  }

  /// 重命名任意项目，并保持项目清单与看板标题一致。
  Future<void> renameProject(String projectId, String title) async {
    return _withBoardMutation(() async {
    final normalized = title.trim();
    final entry = manifest?.findById(projectId);
    if (entry == null || normalized.isEmpty) return;

    final isActive = projectId == activeProjectId;
    final targetBoard =
        isActive ? board : await _repository.loadBoard(projectId);
    if (targetBoard == null) return;
    if (entry.title == normalized && targetBoard.title == normalized) return;

    final nextBoard = _bump(
      targetBoard.copyWith(
        title: normalized,
        clearConflictTitle: true,
      ),
    );
    await _repository.saveBoard(projectId, nextBoard);
    if (isActive) {
      board = nextBoard;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final projects = manifest!.projects.map((project) {
      if (project.id != projectId) return project;
      return project.copyWith(
        title: normalized,
        updatedAt: now,
        revision: project.revision + 1,
        clearConflictTitle: true,
      );
    }).toList();
    manifest = manifest!.bump().copyWith(projects: projects);
    await _repository.saveManifest(manifest!);
    notifyListeners();
    _markWorkspaceChanged();
      });
  }

  Future<void> saveProjectSettings(ProjectSettings settings) async {
    return _withBoardMutation(() async {
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
      });
  }

  /// 为当前看板选择背景图（立即落盘并调度同步）
  Future<String?> setBoardBackgroundFromGallery() async {
    return _withBoardMutation(() async {
    if (board == null || activeProjectId == null) return '看板未就绪';
    final store = attachmentStore;
    if (store == null) return '当前平台不支持图片背景';

    final picked = await pickCardImagesFromGallery();
    if (picked.isEmpty) return null;

    final image = picked.first;
    final CardAttachment attachment;
    try {
      attachment = await store.saveImage(
        projectId: activeProjectId!,
        sourceBytes: image.bytes,
        fileName: image.fileName,
        order: 0,
      );
    } catch (_) {
      return '图片处理失败';
    }

    final previousId = projectSettings.backgroundAttachmentId;
    await _persistProjectSettings(
      projectSettings
          .copyWith(
            backgroundAttachmentId: attachment.id,
            clearConflictSide: true,
          )
          .bump(),
    );

    if (previousId.isNotEmpty && previousId != attachment.id) {
      await store.deleteAttachment(
        projectId: activeProjectId!,
        attachmentId: previousId,
      );
    }
    await refreshMissingAttachments();
    return null;
      });
  }

  /// 清除当前看板背景图
  Future<void> clearBoardBackground() async {
    return _withBoardMutation(() async {
    if (board == null || activeProjectId == null) return;
    final previousId = projectSettings.backgroundAttachmentId;
    if (previousId.isEmpty) return;

    await _persistProjectSettings(
      projectSettings
          .copyWith(
            backgroundAttachmentId: '',
            clearConflictSide: true,
          )
          .bump(),
    );

    final store = attachmentStore;
    if (store != null) {
      await store.deleteAttachment(
        projectId: activeProjectId!,
        attachmentId: previousId,
      );
    }
    await refreshMissingAttachments();
      });
  }

  /// 调整背景遮罩强度（立即落盘并调度同步）
  Future<void> setBoardBackgroundOverlayOpacity(double opacity) async {
    return _withBoardMutation(() async {
    if (board == null) return;
    final next = ProjectSettings.clampOverlayOpacity(opacity);
    if ((projectSettings.backgroundOverlayOpacity - next).abs() < 0.001) {
      return;
    }
    await _persistProjectSettings(
      projectSettings
          .copyWith(
            backgroundOverlayOpacity: next,
            clearConflictSide: true,
          )
          .bump(),
    );
      });
  }

  /// 调整看板卡片表面不透明度（立即落盘并调度同步）
  Future<void> setCardSurfaceOpacity(double opacity) async {
    return _withBoardMutation(() async {
    if (board == null) return;
    final next = ProjectSettings.clampCardSurfaceOpacity(opacity);
    if ((projectSettings.cardSurfaceOpacity - next).abs() < 0.001) {
      return;
    }
    await _persistProjectSettings(
      projectSettings
          .copyWith(
            cardSurfaceOpacity: next,
            clearConflictSide: true,
          )
          .bump(),
    );
      });
  }

  Future<void> updateTitle(String title) async {
    return _withBoardMutation(() async {
    if (board == null) return;
    await _persistAndSync(_bump(board!.copyWith(title: title)));
      });
  }

  /// 新增列；标题 trim 后与现有列精确同名则拒绝，返回错误文案。
  Future<String?> addColumn(
    String title, {
    int? insertIndex,
    String? beforeColumnId,
  }) async {
    return _withBoardMutation(() async {
    if (board == null) return '看板未就绪';
    final normalized = title.trim();
    if (normalized.isEmpty) return '列名称不能为空';
    final columns = [...board!.columns]
      ..sort((a, b) => a.order.compareTo(b.order));
    if (columns.any((col) => col.title == normalized)) {
      return '已存在同名列「$normalized」';
    }
    var index = columns.length;
    if (beforeColumnId != null && beforeColumnId.isNotEmpty) {
      final before = columns.indexWhere((col) => col.id == beforeColumnId);
      if (before >= 0) index = before;
    } else if (insertIndex != null) {
      index = insertIndex.clamp(0, columns.length);
    }
    columns.insert(
      index,
      KanbanColumn(
        id: const Uuid().v4(),
        title: normalized,
        order: index,
        cards: [],
      ),
    );
    final normalizedColumns = [
      for (var i = 0; i < columns.length; i++) columns[i].copyWith(order: i),
    ];
    await _persistAndSync(
      _bump(board!.copyWith(columns: normalizedColumns)),
    );
    return null;
      });
  }

  /// 为当前看板补齐「待返工」列（已有板迁移）；无变更则跳过。
  Future<void> ensureReworkColumn() async {
    return _withBoardMutation(() async {
      await _ensureReworkColumnPersisted();
    });
  }

  Future<void> _ensureReworkColumnPersisted() async {
    final current = board;
    if (current == null) return;
    final next = current.ensureReworkColumn(
      doneColumnTitle: projectSettings.doneColumnName,
    );
    if (identical(next, current)) return;
    final sameShape = next.columns.length == current.columns.length &&
        List.generate(next.columns.length, (i) {
          final a = next.columns[i];
          final b = current.columns[i];
          return a.id == b.id && a.title == b.title && a.order == b.order;
        }).every((ok) => ok);
    if (sameShape) return;
    await _persistAndSync(_bump(next));
  }

  /// 重命名列；与其他列标题冲突时拒绝，返回错误文案。
  Future<String?> renameColumn(String columnId, String title) async {
    return _withBoardMutation(() async {
    if (board == null) return '看板未就绪';
    final normalized = title.trim();
    if (normalized.isEmpty) return '列名称不能为空';
    if (board!.columns.any(
      (col) => col.id != columnId && col.title == normalized,
    )) {
      return '已存在同名列「$normalized」';
    }
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      return col.copyWith(title: normalized);
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
    return null;
      });
  }

  Future<void> reorderColumn(int oldIndex, int newIndex) async {
    return _withBoardMutation(() async {
    if (board == null) return;
    final columns = [...board!.columns];
    if (oldIndex < 0 ||
        oldIndex >= columns.length ||
        newIndex < 0 ||
        newIndex > columns.length) {
      return;
    }

    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex -= 1;
    if (targetIndex == oldIndex) return;

    final moved = columns.removeAt(oldIndex);
    columns.insert(targetIndex, moved);
    final reordered = [
      for (var i = 0; i < columns.length; i++) columns[i].copyWith(order: i),
    ];
    await _persistAndSync(_bump(board!.copyWith(columns: reordered)));
      });
  }

  Future<void> updateColumnColor(String columnId, int? colorValue) async {
    return _withBoardMutation(() async {
    if (board == null) return;
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      return col.copyWith(colorValue: colorValue);
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
      });
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    final mcpChanged = settings.mcpEnabled != appSettings.mcpEnabled ||
        settings.mcpPort != appSettings.mcpPort;
    final autoClearChanged =
        settings.completedAutoClearDays != appSettings.completedAutoClearDays;
    appSettings = settings;
    await _repository.saveAppSettings(settings);
    notifyListeners();
    if (mcpChanged) {
      await _syncMcpHost();
    }
    if (autoClearChanged && settings.completedAutoClearDays > 0) {
      unawaited(purgeExpiredCompletedCards(force: true));
    }
  }

  Future<String> addCustomLabel(String name, int colorValue) async {
    return _withBoardMutation(() async {
    final key = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final label = SharedLabel(
      id: key,
      name: name,
      colorValue: colorValue,
      updatedAt: now,
    );
    await _persistSharedContent(
      sharedContent.copyWith(labels: [...sharedContent.labels, label]),
    );
    return key;
      });
  }

  /// 修改自定义标签名称或颜色；标签 key 不变，已有卡片引用无需迁移。
  Future<bool> updateCustomLabel(
    String key, {
    required String name,
    required int colorValue,
  }) async {
    return _withBoardMutation(() async {
    final normalized = name.trim();
    if (normalized.isEmpty) return false;
    final index =
        appSettings.customLabels.indexWhere((label) => label.key == key);
    if (index < 0) return false;

    final labels = [...sharedContent.labels];
    final sharedIndex = labels.indexWhere((label) => label.id == key);
    if (sharedIndex < 0) return false;
    labels[sharedIndex] = SharedLabel(
      id: key,
      name: normalized,
      colorValue: colorValue,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _persistSharedContent(sharedContent.copyWith(labels: labels));
    return true;
      });
  }

  Future<void> removeCustomLabel(String key) async {
    return _withBoardMutation(() async {
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

    await _persistSharedContent(
      sharedContent.copyWith(
        labels: sharedContent.labels.where((label) => label.id != key).toList(),
      ),
    );
      });
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
    return _withBoardMutation(() async {
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

    final columns = board!.columns.where((col) => col.id != columnId).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
      });
  }

  Future<bool> deleteProject(String projectId) async {
    return _withBoardMutation(() async {
    if (manifest == null || manifest!.projects.length <= 1) return false;

    final entry = manifest!.findById(projectId);
    if (entry == null) return false;

    final projectBoard = projectId == activeProjectId
        ? board!
        : await _repository.loadBoard(projectId);
    final settings = projectId == activeProjectId
        ? projectSettings
        : await _repository.loadProjectSettings(projectId);
    final trash = projectTrashes[projectId] ??
        await _repository.loadProjectTrash(projectId);

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
    projectThemeIds.remove(projectId);

    if (activeProjectId == projectId) {
      final next = remaining.first;
      activeProjectId = next.id;
      await _repository.saveActiveProjectId(next.id);
      board = await _repository.loadBoard(next.id);
      projectSettings = await _repository.loadProjectSettings(next.id);
      projectThemeIds[next.id] = projectSettings.themeId;
      activeProjectTrash = projectTrashes[next.id] ?? TrashBin.empty;
    }

    await _persistAppTrash();
    notifyListeners();
    return true;
      });
  }

  /// 后台删除项目，但绝不删除或切换界面当前项目。
  Future<bool> deleteProjectInBackground(String projectId) {
    return _withBoardMutation(() async {
      if (projectId == _uiActiveProjectId) return false;
      return deleteProject(projectId);
    });
  }

  Future<String?> addCard(
    String columnId,
    String title, {
    String? description,
    int? dueDate,
    int? reminderAt,
    CardRecurrence recurrence = CardRecurrence.none,
    CardPriority priority = CardPriority.none,
    List<String> labels = const [],
  }) async {
    return _withBoardMutation(() async {
    if (board == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cardId = const Uuid().v4();
    var added = false;
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      added = true;
      final cards = [
        ...col.cards,
        KanbanCard(
          id: cardId,
          title: title,
          description: description,
          order: col.cards.length,
          createdAt: now,
          updatedAt: now,
          dueDate: dueDate,
          reminderAt: reminderAt,
          recurrence: recurrence,
          recurrenceSeriesId: recurrence == CardRecurrence.none ? null : cardId,
          priority: priority,
          labels: labels,
        ),
      ];
      return col.copyWith(cards: cards);
    }).toList();
    if (!added) return null;
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
    String? trashId;
    _pushUndo(
      '新建「$title」',
      () async {
        trashId = await deleteCard(columnId, cardId);
      },
      redo: () async {
        final id = trashId;
        if (id == null) return;
        final error = await restoreTrashItem(id);
        if (error != null) throw StateError(error);
      },
    );
    if (reminderAt != null && activeProjectId != null) {
      await _scheduleCardReminder(
        projectId: activeProjectId!,
        columnId: columnId,
        card: columns
            .firstWhere((column) => column.id == columnId)
            .cards
            .firstWhere((card) => card.id == cardId),
      );
    }
    await _recordActivity(
      entityId: cardId,
      entityTitle: title,
      action: ActivityAction.created,
    );
    return cardId;
      });
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

  /// 更新卡片。规则门禁拒绝时返回简体中文原因，成功返回 `null`。
  Future<String?> updateCardFull(
    String columnId,
    String cardId, {
    String? title,
    String? description,
    bool clearDescription = false,
    bool? completed,
    int? dueDate,
    bool clearDueDate = false,
    int? reminderAt,
    bool clearReminder = false,
    CardRecurrence? recurrence,
    int? recurrenceInterval,
    CardPriority? priority,
    List<String>? labels,
    List<ChecklistItem>? checklist,
    List<ChecklistItem>? verificationFeedback,
    List<CardAttachment>? attachments,
    List<CardLink>? links,
    List<String>? blockedByIds,
    List<String>? relatedIds,
    int? colorValue,
    bool clearColor = false,
  }) async {
    return _withBoardMutation(() async {
    if (board == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final original = board!.columns
        .where((column) => column.id == columnId)
        .expand((column) => column.cards)
        .where((card) => card.id == cardId)
        .firstOrNull;
    if (original == null) return null;
    final nextVerificationFeedback =
        verificationFeedback ?? original.verificationFeedback;
    if (completed == true &&
        hasIncompleteVerificationFeedback(nextVerificationFeedback)) {
      return incompleteVerificationFeedbackBlocksProgressMessage;
    }
    // 未完成反馈是流程权威状态：即使旧数据已完成，也必须恢复未完成态。
    final nextCompleted = hasIncompleteVerificationFeedback(
      nextVerificationFeedback,
    )
        ? false
        : (completed ?? original.completed);
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      final cards = col.cards.map((card) {
        if (card.id != cardId) return card;
        return card.copyWith(
          title: title ?? card.title,
          description:
              clearDescription ? null : (description ?? card.description),
          completed: nextCompleted,
          completedAt: nextCompleted ? (card.completedAt ?? now) : null,
          dueDate: clearDueDate ? null : (dueDate ?? card.dueDate),
          reminderAt: clearReminder ? null : (reminderAt ?? card.reminderAt),
          recurrence: recurrence ?? card.recurrence,
          recurrenceInterval: recurrenceInterval ?? card.recurrenceInterval,
          priority: priority ?? card.priority,
          labels: labels ?? card.labels,
          checklist: checklist ?? card.checklist,
          verificationFeedback: nextVerificationFeedback,
          attachments: attachments ?? card.attachments,
          links: links ?? card.links,
          blockedByIds: blockedByIds ?? card.blockedByIds,
          relatedIds: relatedIds ?? card.relatedIds,
          colorValue: clearColor ? null : (colorValue ?? card.colorValue),
          updatedAt: now,
        );
      }).toList();
      return col.copyWith(cards: cards);
    }).toList();
    await _persistAndSync(
      _bump(board!.copyWith(columns: _normalizeOrders(columns))),
    );
    if (!_applyingAutomation) {
        final restoredTitle = title ?? original.title;
        final restoredDescription =
            clearDescription ? null : (description ?? original.description);
        final restoredCompleted = nextCompleted;
        final restoredDueDate =
            clearDueDate ? null : (dueDate ?? original.dueDate);
        final restoredReminderAt =
            clearReminder ? null : (reminderAt ?? original.reminderAt);
        final restoredRecurrence = recurrence ?? original.recurrence;
        final restoredRecurrenceInterval =
            recurrenceInterval ?? original.recurrenceInterval;
        final restoredPriority = priority ?? original.priority;
        final restoredLabels = labels ?? original.labels;
        final restoredChecklist = checklist ?? original.checklist;
        final restoredVerification =
            verificationFeedback ?? original.verificationFeedback;
        final restoredAttachments = attachments ?? original.attachments;
        final restoredLinks = links ?? original.links;
        final restoredBlockedBy = blockedByIds ?? original.blockedByIds;
        final restoredRelated = relatedIds ?? original.relatedIds;
        final restoredColor =
            clearColor ? null : (colorValue ?? original.colorValue);
        _pushUndo(
          '编辑「${original.title}」',
          () async {
            final error = await updateCardFull(
            columnId,
            cardId,
            title: original.title,
            description: original.description,
            clearDescription: original.description == null,
            completed: original.completed,
            dueDate: original.dueDate,
            clearDueDate: original.dueDate == null,
            reminderAt: original.reminderAt,
            clearReminder: original.reminderAt == null,
            recurrence: original.recurrence,
            recurrenceInterval: original.recurrenceInterval,
            priority: original.priority,
            labels: original.labels,
            checklist: original.checklist,
            verificationFeedback: original.verificationFeedback,
            attachments: original.attachments,
            links: original.links,
            blockedByIds: original.blockedByIds,
            relatedIds: original.relatedIds,
            colorValue: original.colorValue,
            clearColor: original.colorValue == null,
            );
            if (error != null) throw StateError(error);
          },
          redo: () async {
            final error = await updateCardFull(
            columnId,
            cardId,
            title: restoredTitle,
            description: restoredDescription,
            clearDescription: restoredDescription == null,
            completed: restoredCompleted,
            dueDate: restoredDueDate,
            clearDueDate: restoredDueDate == null,
            reminderAt: restoredReminderAt,
            clearReminder: restoredReminderAt == null,
            recurrence: restoredRecurrence,
            recurrenceInterval: restoredRecurrenceInterval,
            priority: restoredPriority,
            labels: restoredLabels,
            checklist: restoredChecklist,
            verificationFeedback: restoredVerification,
            attachments: restoredAttachments,
            links: restoredLinks,
            blockedByIds: restoredBlockedBy,
            relatedIds: restoredRelated,
            colorValue: restoredColor,
            clearColor: restoredColor == null,
            );
            if (error != null) throw StateError(error);
          },
        );
    }
    await _recordActivity(
      entityId: cardId,
      entityTitle: title ?? original.title,
      action: ActivityAction.updated,
    );
    await _rescheduleReminders();

    if (!_applyingAutomation) {
      final updated = board!.columns
          .where((column) => column.id == columnId)
          .expand((column) => column.cards)
          .where((card) => card.id == cardId)
          .firstOrNull;
      if (updated != null) {
        if (nextCompleted && !original.completed) {
          await _runAutomations(
            _automationEngine.effectsForCompleted(
              rules: projectSettings.automationRules,
              card: updated,
            ),
            columnId: columnId,
            cardId: cardId,
          );
        }
        final checklistChanged = checklist != null;
        if (checklistChanged) {
          await _runAutomations(
            _automationEngine.effectsForChecklistAllDone(
              rules: projectSettings.automationRules,
              card: updated,
            ),
            columnId: columnId,
            cardId: cardId,
          );
        }
      }
    }
    if (hasIncompleteVerificationFeedback(nextVerificationFeedback)) {
      await ensureReworkColumn();
      final currentColumnId = findColumnIdForCard(cardId);
      final currentBoard = board;
      final rework = currentBoard == null
          ? null
          : findReworkColumn(currentBoard.columns);
      if (currentColumnId != null &&
          rework != null &&
          currentColumnId != rework.id) {
        await moveCard(
          cardId: cardId,
          fromColumnId: currentColumnId,
          toColumnId: rework.id,
          toDisplayIndex: rework.cards.length,
        );
      }
    }
    return null;
      });
  }

  /// 按卡片 id 查找所属列。
  String? findColumnIdForCard(String cardId) {
    final current = board;
    if (current == null) return null;
    for (final column in current.columns) {
      if (column.cards.any((card) => card.id == cardId)) {
        return column.id;
      }
    }
    return null;
  }

  KanbanCard? findCardById(String cardId) {
    final current = board;
    if (current == null) return null;
    for (final column in current.columns) {
      for (final card in column.cards) {
        if (card.id == cardId) return card;
      }
    }
    return null;
  }

  Future<void> _runAutomations(
    List<AutomationEffect> effects, {
    required String columnId,
    required String cardId,
  }) async {
    if (effects.isEmpty || _applyingAutomation || board == null) return;
    _applyingAutomation = true;
    try {
      for (final effect in effects) {
        final card = findCardById(cardId);
        final currentColumnId = findColumnIdForCard(cardId);
        if (card == null || currentColumnId == null) return;

        if (effect.moveToDone) {
          final done = _findDoneColumn(board!);
          if (done != null && done.id != currentColumnId) {
            await moveCard(
              cardId: cardId,
              fromColumnId: currentColumnId,
              toColumnId: done.id,
              toDisplayIndex: done.cards.length,
              completed: true,
              completedAt: DateTime.now().millisecondsSinceEpoch,
            );
          } else {
            await updateCardFull(
              currentColumnId,
              cardId,
              completed: true,
            );
          }
          continue;
        }

        var nextLabels = card.labels;
        if (effect.addLabelKey != null &&
            !nextLabels.contains(effect.addLabelKey)) {
          nextLabels = [...nextLabels, effect.addLabelKey!];
        }
        await updateCardFull(
          currentColumnId,
          cardId,
          completed: effect.completed,
          priority: effect.priority,
          labels: effect.addLabelKey == null ? null : nextLabels,
          clearReminder: effect.clearReminder,
        );
      }
    } finally {
      _applyingAutomation = false;
    }
  }

  /// 扫描并执行「已逾期」自动化。
  Future<void> runOverdueAutomations() async {
    if (board == null) return;
    final now = DateTime.now();
    for (final column in [...board!.columns]) {
      for (final card in [...column.cards]) {
        final effects = _automationEngine.effectsForOverdue(
          rules: projectSettings.automationRules,
          card: card,
          now: now,
        );
        if (effects.isEmpty) continue;
        await _runAutomations(
          effects,
          columnId: column.id,
          cardId: card.id,
        );
      }
    }
  }

  Future<String?> addCardAttachmentsFromSource(
    String columnId,
    String cardId,
    CardImageAddSource source,
  ) async {
    return _withBoardMutation(() async {
    final picked = await pickImagesForSource(source);
    if (picked.isEmpty) {
      return switch (source) {
        CardImageAddSource.clipboard => '剪贴板中没有图片',
        _ => null,
      };
    }
    return addCardAttachments(
      columnId,
      cardId,
      pickImages: () async => picked,
    );
      });
  }

  Future<String?> addCardAttachments(
    String columnId,
    String cardId, {
    Future<List<PickedImageBytes>> Function()? pickImages,
  }) async {
    return _withBoardMutation(() async {
    if (board == null || activeProjectId == null) return '看板未就绪';

    KanbanCard? target;
    for (final col in board!.columns) {
      if (col.id != columnId) continue;
      for (final card in col.cards) {
        if (card.id == cardId) {
          target = card;
          break;
        }
      }
    }
    if (target == null) return '卡片不存在';

    final store = attachmentStore;
    if (store == null) return '当前平台不支持图片附件';

    final remaining = KanbanCard.maxAttachments - target.attachments.length;
    if (remaining <= 0) {
      return '每张卡片最多 ${KanbanCard.maxAttachments} 张图片';
    }

    final picked = await (pickImages ?? pickCardImagesFromGallery)();
    if (picked.isEmpty) return null;

    final nextAttachments = [...target.attachments];
    var nextOrder = nextAttachments.isEmpty
        ? 0
        : nextAttachments.map((a) => a.order).reduce((a, b) => a > b ? a : b) +
            1;

    try {
      for (final image in picked) {
        if (nextAttachments.length >= KanbanCard.maxAttachments) break;
        final attachment = await store.saveImage(
          projectId: activeProjectId!,
          sourceBytes: image.bytes,
          fileName: image.fileName,
          order: nextOrder,
        );
        nextAttachments.add(attachment);
        nextOrder++;
      }
    } catch (e) {
      return '图片处理失败';
    }

    await updateCardFull(
      columnId,
      cardId,
      attachments: nextAttachments,
    );
    await refreshMissingAttachments();
    return null;
      });
  }

  Future<void> reorderCardAttachments(
    String columnId,
    String cardId,
    List<CardAttachment> ordered,
  ) async {
    return _withBoardMutation(() async {
    await updateCardFull(
      columnId,
      cardId,
      attachments: _reindexAttachments(ordered),
    );
      });
  }

  Future<void> removeCardAttachment(
    String columnId,
    String cardId,
    String attachmentId,
  ) async {
    return _withBoardMutation(() async {
    if (board == null || activeProjectId == null) return;

    KanbanCard? target;
    for (final col in board!.columns) {
      if (col.id != columnId) continue;
      for (final card in col.cards) {
        if (card.id == cardId) {
          target = card;
          break;
        }
      }
    }
    if (target == null) return;

    final nextAttachments = target.attachments
        .where((attachment) => attachment.id != attachmentId)
        .toList();
    if (nextAttachments.length == target.attachments.length) return;

    await updateCardFull(
      columnId,
      cardId,
      attachments: _reindexAttachments(nextAttachments),
    );
    await attachmentStore?.deleteAttachment(
      projectId: activeProjectId!,
      attachmentId: attachmentId,
    );
    await refreshMissingAttachments();
    _markWorkspaceChanged();
      });
  }

  Future<void> setCardAttachmentCover(
    String columnId,
    String cardId,
    String attachmentId,
  ) async {
    return _withBoardMutation(() async {
    if (board == null) return;

    KanbanCard? target;
    for (final col in board!.columns) {
      if (col.id != columnId) continue;
      for (final card in col.cards) {
        if (card.id == cardId) {
          target = card;
          break;
        }
      }
    }
    if (target == null) return;

    final selected = target.attachments
        .where((attachment) => attachment.id == attachmentId)
        .toList();
    if (selected.isEmpty) return;

    final others = target.attachments
        .where((attachment) => attachment.id != attachmentId)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final nextAttachments = [
      selected.first.copyWith(order: 0),
      for (var i = 0; i < others.length; i++) others[i].copyWith(order: i + 1),
    ];

    await updateCardFull(
      columnId,
      cardId,
      attachments: nextAttachments,
    );
      });
  }

  List<CardAttachment> _reindexAttachments(List<CardAttachment> attachments) {
    final sorted = [...attachments]..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(order: i),
    ];
  }

  /// 切换完成状态。仍有未完成验证反馈时拒绝完成并返回原因。
  Future<String?> toggleCardCompleted(String columnId, String cardId) async {
    return _withBoardMutation(() async {
    if (board == null) return null;
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
    if (target == null) return null;

    final nextCompleted = !target.completed;
    if (nextCompleted &&
        hasIncompleteVerificationFeedback(target.verificationFeedback)) {
      return incompleteVerificationFeedbackBlocksProgressMessage;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final doneColumn = _findDoneColumn(current);

    if (nextCompleted && doneColumn != null && doneColumn.id != columnId) {
      final moveError = await moveCard(
        cardId: cardId,
        fromColumnId: columnId,
        toColumnId: doneColumn.id,
        toDisplayIndex: doneColumn.cards.length,
        completed: true,
        completedAt: now,
      );
      if (moveError != null) return moveError;
      await _afterCompletionChanged(
        target,
        sourceColumnId: columnId,
        completed: true,
      );
      return null;
    }

    if (!nextCompleted && doneColumn?.id == columnId) {
      final todoColumn = current.columns.cast<KanbanColumn?>().firstWhere(
            (col) => col!.id == 'todo',
            orElse: () =>
                current.columns.isNotEmpty ? current.columns.first : null,
          );
      if (todoColumn != null && todoColumn.id != columnId) {
        final moveError = await moveCard(
          cardId: cardId,
          fromColumnId: columnId,
          toColumnId: todoColumn.id,
          toDisplayIndex: todoColumn.cards.length,
          completed: false,
          completedAt: null,
        );
        if (moveError != null) return moveError;
        await _afterCompletionChanged(
          target,
          sourceColumnId: columnId,
          completed: false,
        );
        return null;
      }
    }

    final updateError =
        await updateCardFull(columnId, cardId, completed: nextCompleted);
    if (updateError != null) return updateError;
    await _afterCompletionChanged(
      target,
      sourceColumnId: columnId,
      completed: nextCompleted,
    );
    return null;
      });
  }

  Future<void> _afterCompletionChanged(
    KanbanCard card, {
    required String sourceColumnId,
    required bool completed,
  }) async {
    await _reminderScheduler.cancel(card.id);
    if (completed) {
      final next = _recurrenceService.createNextOccurrence(card);
      if (next != null &&
          board != null &&
          !board!.columns.any(
            (column) => column.cards.any((item) => item.id == next.id),
          )) {
        final columns = board!.columns.map((column) {
          if (column.id != sourceColumnId) return column;
          return column.copyWith(
            cards: [
              ...column.cards,
              next.copyWith(order: column.cards.length),
            ],
          );
        }).toList();
        await _persistAndSync(_bump(board!.copyWith(columns: columns)));
        if (next.reminderAt != null && activeProjectId != null) {
          await _scheduleCardReminder(
            projectId: activeProjectId!,
            columnId: sourceColumnId,
            card: next,
          );
        }
      }
    }
    await _recordActivity(
      entityId: card.id,
      entityTitle: card.title,
      action: completed ? ActivityAction.completed : ActivityAction.reopened,
    );
  }

  Future<String?> deleteCard(String columnId, String cardId) async {
    return _withBoardMutation(() async {
    if (board == null || activeProjectId == null) return null;

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
    if (target == null || sourceColumn == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final trashId = const Uuid().v4();
    await _addToActiveProjectTrash(
      TrashItem.forCard(
        trashId: trashId,
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
    await _reminderScheduler.cancel(cardId);
    var currentTrashId = trashId;
    _pushUndo(
      '删除「${target.title}」',
      () async {
        final error = await restoreTrashItem(currentTrashId);
        if (error != null) throw StateError(error);
      },
      redo: () async {
        final id = await deleteCard(columnId, cardId);
        if (id != null) currentTrashId = id;
      },
    );
    await _recordActivity(
      entityId: cardId,
      entityTitle: target.title,
      action: ActivityAction.deleted,
    );
    return trashId;
      });
  }

  /// 将卡片从源项目转移到目标项目（默认落入目标「待办」列）。
  ///
  /// 成功返回 `null`，失败返回简体中文错误说明。
  /// [sourceProjectId] 省略时使用界面当前项目（[uiActiveProjectId]）。
  /// [targetColumnId] 省略时按 [resolveTransferTargetColumnId] 解析
  ///（优先源列同名标题，否则待办，再兜底）。
  Future<String?> transferCardToProject({
    required String fromColumnId,
    required String cardId,
    required String targetProjectId,
    String? sourceProjectId,
    String? targetColumnId,
  }) async {
    return _withBoardMutation(() async {
      final fromProjectId =
          sourceProjectId ?? _uiActiveProjectId ?? activeProjectId;
      if (fromProjectId == null) return '看板未就绪';
      if ((manifest?.projects.length ?? 0) <= 1) {
        return '没有其他可转移的项目';
      }
      if (targetProjectId == fromProjectId) return '不能转移到当前项目';
      if (manifest?.findById(targetProjectId) == null) {
        return '目标项目不存在';
      }
      if (manifest?.findById(fromProjectId) == null) {
        return '源项目不存在';
      }

      final fromBoard = await _loadBoardForTransfer(fromProjectId);
      if (fromBoard == null) return '无法加载源项目';

      KanbanCard? moving;
      for (final col in fromBoard.columns) {
        if (col.id != fromColumnId) continue;
        for (final card in col.cards) {
          if (card.id == cardId) {
            moving = card;
            break;
          }
        }
      }
      if (moving == null) return '卡片不存在';

      final toBoardLoaded = await _loadBoardForTransfer(targetProjectId);
      if (toBoardLoaded == null) return '无法加载目标项目';

      final toSettings = targetProjectId == activeProjectId
          ? projectSettings
          : await _repository.loadProjectSettings(targetProjectId);
      String? sourceColumnTitle;
      for (final col in fromBoard.columns) {
        if (col.id == fromColumnId) {
          sourceColumnTitle = col.title;
          break;
        }
      }
      final resolvedTargetColumnId = targetColumnId ??
          resolveTransferTargetColumnId(
            toBoardLoaded,
            sourceColumnTitle: sourceColumnTitle,
            doneColumnName: toSettings.doneColumnName,
          );
      if (resolvedTargetColumnId == null) return '目标项目没有可用列';
      if (!toBoardLoaded.columns.any((c) => c.id == resolvedTargetColumnId)) {
        return '目标列不存在';
      }
      if (toBoardLoaded.columns
          .any((c) => c.cards.any((card) => card.id == cardId))) {
        return '目标项目已存在相同卡片';
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final targetDone = findDoneColumn(
        toBoardLoaded,
        doneColumnName: toSettings.doneColumnName,
      );
      final landingOnDone = targetDone?.id == resolvedTargetColumnId;
      final targetColumn = toBoardLoaded.columns
          .firstWhere((c) => c.id == resolvedTargetColumnId);

      final transferred = moving.copyWith(
        order: targetColumn.cards.length,
        updatedAt: now,
        completed: landingOnDone,
        completedAt: landingOnDone ? (moving.completedAt ?? now) : null,
        // 依赖/关联指向源项目内卡片，跨项目后清空避免悬空引用
        blockedByIds: const [],
        relatedIds: const [],
        clearConflict: true,
      );

      final copyError = await _copyCardAttachmentsBetweenProjects(
        fromProjectId: fromProjectId,
        toProjectId: targetProjectId,
        attachments: moving.attachments,
      );
      if (copyError != null) return copyError;

      final fromPrefs = fromProjectId == activeProjectId
          ? columnPreferencesFor(fromColumnId)
          : (await _repository.loadProjectSettings(fromProjectId))
              .columnPreferencesFor(fromColumnId);
      final nextFromPinned = [...fromPrefs.pinnedCardIds]..remove(cardId);
      if (nextFromPinned.length != fromPrefs.pinnedCardIds.length) {
        await _updateColumnPinnedForProject(
          projectId: fromProjectId,
          columnId: fromColumnId,
          pinnedCardIds: nextFromPinned,
        );
      }

      final nextFromColumns = fromBoard.columns.map((col) {
        if (col.id != fromColumnId) return col;
        return col.copyWith(
          cards: col.cards.where((c) => c.id != cardId).toList(),
        );
      }).toList();
      await _writeBoardForTransfer(
        fromProjectId,
        _bump(fromBoard.copyWith(columns: nextFromColumns)),
      );

      final nextToColumns = toBoardLoaded.columns.map((col) {
        if (col.id != resolvedTargetColumnId) return col;
        return col.copyWith(cards: [...col.cards, transferred]);
      }).toList();
      await _writeBoardForTransfer(
        targetProjectId,
        _bump(toBoardLoaded.copyWith(columns: nextToColumns)),
      );

      final store = attachmentStore;
      if (store != null && moving.attachments.isNotEmpty) {
        await store.deleteAttachments(
          projectId: fromProjectId,
          attachments: moving.attachments,
        );
      }

      await _reminderScheduler.cancel(cardId);
      if (transferred.reminderAt != null && !transferred.completed) {
        await _scheduleCardReminder(
          projectId: targetProjectId,
          columnId: resolvedTargetColumnId,
          card: transferred,
        );
      }

      final targetTitle =
          manifest?.findById(targetProjectId)?.title ?? targetProjectId;
      final sourceTitle =
          manifest?.findById(fromProjectId)?.title ?? fromProjectId;
      await _recordActivity(
        entityId: cardId,
        entityTitle: moving.title,
        action: ActivityAction.moved,
        details: {
          'transfer': 'project',
          'fromProjectId': fromProjectId,
          'toProjectId': targetProjectId,
          'fromColumnId': fromColumnId,
          'toColumnId': resolvedTargetColumnId,
          'fromProjectTitle': sourceTitle,
          'toProjectTitle': targetTitle,
        },
      );

      _pushUndo(
        '转移「${moving.title}」到「$targetTitle」',
        () async {
          final error = await transferCardToProject(
            fromColumnId: resolvedTargetColumnId,
            cardId: cardId,
            targetProjectId: fromProjectId,
            sourceProjectId: targetProjectId,
            targetColumnId: fromColumnId,
          );
          if (error != null) throw StateError(error);
        },
        redo: () async {
          final error = await transferCardToProject(
            fromColumnId: fromColumnId,
            cardId: cardId,
            targetProjectId: targetProjectId,
            sourceProjectId: fromProjectId,
            targetColumnId: resolvedTargetColumnId,
          );
          if (error != null) throw StateError(error);
        },
      );

      return null;
    });
  }

  Future<KanbanBoard?> _loadBoardForTransfer(String projectId) async {
    if (projectId == activeProjectId) return board;
    if (projectId == _uiActiveProjectId) return _uiBoard;
    return _repository.loadBoard(projectId);
  }

  Future<void> _writeBoardForTransfer(
    String projectId,
    KanbanBoard next,
  ) async {
    await _repository.saveBoard(projectId, next);
    if (_projectMutationScope != null &&
        projectId == _projectMutationScope!.projectId) {
      board = next;
    } else if (projectId == _uiActiveProjectId) {
      _uiBoard = next;
    }
    notifyListeners();
    _markWorkspaceChanged();
  }

  Future<String?> _copyCardAttachmentsBetweenProjects({
    required String fromProjectId,
    required String toProjectId,
    required List<CardAttachment> attachments,
  }) async {
    if (attachments.isEmpty) return null;
    final store = attachmentStore;
    if (store == null) return null;
    try {
      for (final attachment in attachments) {
        final bytes = await store.readBytes(
          projectId: fromProjectId,
          attachmentId: attachment.id,
        );
        if (bytes != null) {
          await store.writeBytes(
            projectId: toProjectId,
            attachmentId: attachment.id,
            bytes: bytes,
          );
        }
        final thumb = await store.readBytes(
          projectId: fromProjectId,
          attachmentId: attachment.id,
          thumb: true,
        );
        if (thumb != null) {
          await store.writeBytes(
            projectId: toProjectId,
            attachmentId: attachment.id,
            bytes: thumb,
            thumb: true,
          );
        }
      }
    } catch (error) {
      debugPrint('转移卡片附件失败：$error');
      return '转移附件失败';
    }
    return null;
  }

  Future<void> _updateColumnPinnedForProject({
    required String projectId,
    required String columnId,
    required List<String> pinnedCardIds,
  }) async {
    if (projectId == activeProjectId) {
      final prefs = columnPreferencesFor(columnId);
      await _persistProjectSettings(
        projectSettings.bump().copyWith(
          columnPreferences: {
            ...projectSettings.columnPreferences,
            columnId: prefs.copyWith(pinnedCardIds: pinnedCardIds),
          },
        ),
      );
      return;
    }
    final settings = await _repository.loadProjectSettings(projectId);
    final prefs = settings.columnPreferencesFor(columnId);
    final next = settings.bump().copyWith(
      columnPreferences: {
        ...settings.columnPreferences,
        columnId: prefs.copyWith(pinnedCardIds: pinnedCardIds),
      },
    );
    await _repository.saveProjectSettings(projectId, next);
    _markWorkspaceChanged();
  }

  /// 清空已完成列中的全部卡片（移入回收站）。仅当 [columnId] 为当前项目的已完成列时生效。
  /// 返回实际清空的卡片数量。
  Future<int> clearDoneColumnCards(String columnId) async {
    return _withBoardMutation(() async {
    if (board == null || activeProjectId == null) return 0;

    final doneColumn = _findDoneColumn(board!);
    if (doneColumn == null || doneColumn.id != columnId) return 0;
    if (doneColumn.cards.isEmpty) return 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final trashIds = <String>[];
    final newTrashItems = <TrashItem>[];
    final clearedCards = List<KanbanCard>.from(doneColumn.cards);

    for (final card in clearedCards) {
      final trashId = const Uuid().v4();
      trashIds.add(trashId);
      newTrashItems.add(
        TrashItem.forCard(
          trashId: trashId,
          deletedAt: now,
          projectId: activeProjectId!,
          projectTitle: board!.title,
          columnId: columnId,
          columnTitle: doneColumn.title,
          card: card,
        ),
      );
    }

    activeProjectTrash = activeProjectTrash.bump().copyWith(
      items: [...newTrashItems, ...activeProjectTrash.items],
    );
    await _persistActiveProjectTrash();

    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      return col.copyWith(cards: const <KanbanCard>[]);
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));

    for (final card in clearedCards) {
      await _reminderScheduler.cancel(card.id);
      await _recordActivity(
        entityId: card.id,
        entityTitle: card.title,
        action: ActivityAction.deleted,
      );
    }

    final count = clearedCards.length;
    final clearedCardIds = [for (final card in clearedCards) card.id];
    var currentTrashIds = List<String>.from(trashIds);
    _pushUndo(
      '清空「${doneColumn.title}」($count)',
      () async {
        for (final trashId in currentTrashIds.reversed) {
          final error = await restoreTrashItem(trashId);
          if (error != null) throw StateError(error);
        }
      },
      redo: () async {
        final nextIds = <String>[];
        for (final cardId in clearedCardIds) {
          final id = await deleteCard(columnId, cardId);
          if (id != null) nextIds.add(id);
        }
        currentTrashIds = nextIds;
      },
    );
    return count;
      });
  }

  /// 扫描全部项目，将超过保留天数的已完成列卡片移入回收站。
  ///
  /// [force] 为 true 时忽略节流（例如用户刚改了保留天数）。
  /// 返回实际移入回收站的卡片数量。
  Future<int> purgeExpiredCompletedCards({bool force = false}) async {
    final days = appSettings.completedAutoClearDays;
    if (days <= 0) return 0;
    if (isLoading || errorMessage != null) return 0;
    if (_completedAutoClearRunning) return 0;

    final now = DateTime.now();
    if (!force) {
      final last = _lastCompletedAutoClearAt;
      if (last != null &&
          now.difference(last) < completedAutoClearMinInterval) {
        return 0;
      }
    }

    _completedAutoClearRunning = true;
    _lastCompletedAutoClearAt = now;
    var total = 0;
    try {
      final projects =
          List<ProjectEntry>.from(manifest?.projects ?? const <ProjectEntry>[]);
      for (final entry in projects) {
        try {
          total += await runOnProject(
            entry.id,
            () => _purgeExpiredCompletedInCurrentProject(days, now),
          );
        } catch (error) {
          debugPrint('自动清空已完成失败（${entry.title}）：$error');
        }
      }
      if (total > 0) {
        debugPrint('自动清空已完成：$total 张卡片已移入回收站');
      }
      return total;
    } finally {
      _completedAutoClearRunning = false;
    }
  }

  Future<int> _purgeExpiredCompletedInCurrentProject(
    int days,
    DateTime now,
  ) async {
    final current = board;
    final projectId = activeProjectId;
    if (current == null || projectId == null) return 0;

    final expired = selectExpiredCompletedCards(
      board: current,
      doneColumnName: projectSettings.doneColumnName,
      retainDays: days,
      now: now,
    );
    if (expired.isEmpty) return 0;

    final doneColumn = findDoneColumn(
      current,
      doneColumnName: projectSettings.doneColumnName,
    );
    if (doneColumn == null) return 0;

    final expiredIds = {for (final card in expired) card.id};
    final deletedAt = now.millisecondsSinceEpoch;
    final newTrashItems = <TrashItem>[
      for (final card in expired)
        TrashItem.forCard(
          trashId: const Uuid().v4(),
          deletedAt: deletedAt,
          projectId: projectId,
          projectTitle: current.title,
          columnId: doneColumn.id,
          columnTitle: doneColumn.title,
          card: card,
        ),
    ];

    activeProjectTrash = activeProjectTrash.bump().copyWith(
      items: [...newTrashItems, ...activeProjectTrash.items],
    );
    await _persistActiveProjectTrash();

    final columns = current.columns.map((col) {
      if (col.id != doneColumn.id) return col;
      return col.copyWith(
        cards: [
          for (final card in col.cards)
            if (!expiredIds.contains(card.id)) card,
        ],
      );
    }).toList();
    await _persistAndSync(_bump(current.copyWith(columns: columns)));

    for (final card in expired) {
      await _reminderScheduler.cancel(card.id);
      await _recordActivity(
        entityId: card.id,
        entityTitle: card.title,
        action: ActivityAction.deleted,
        source: ActivitySource.automation,
      );
    }
    return expired.length;
  }

  /// 移动卡片。规则门禁拒绝时返回简体中文原因，成功返回 `null`。
  Future<String?> moveCard({
    required String cardId,
    required String fromColumnId,
    required String toColumnId,
    required int toDisplayIndex,
    bool? completed,
    int? completedAt,
  }) async {
    return _withBoardMutation(() async {
    if (board == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final fromPrefs = columnPreferencesFor(fromColumnId);
    final toPrefs = columnPreferencesFor(toColumnId);

    if (fromColumnId == toColumnId &&
        fromPrefs.sortMode != CardSortMode.custom) {
      return null;
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

    if (moving == null) return null;

    final reworkRejection = reworkMoveRejectionReason(
      fromColumnId: fromColumnId,
      toColumnId: toColumnId,
      verificationFeedback: moving!.verificationFeedback,
      columns: board!.columns,
      doneColumnName: projectSettings.doneColumnName,
    );
    if (reworkRejection != null) return reworkRejection;

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
        completedAt: markDone ? (cardToInsert.completedAt ?? now) : null,
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

      final targetPinned = nextPinnedByColumn[toColumnId]?.pinnedCardIds ??
          toPrefs.pinnedCardIds;
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

      nextPinnedByColumn[toColumnId] =
          (nextPinnedByColumn[toColumnId] ?? toPrefs)
              .copyWith(pinnedCardIds: derived.pinned);

      return col.copyWith(cards: cards);
    }).toList();

    if (nextPinnedByColumn != projectSettings.columnPreferences) {
      projectSettings = projectSettings.bump().copyWith(
            columnPreferences: nextPinnedByColumn,
          );
      if (activeProjectId != null) {
        await _repository.saveProjectSettings(
            activeProjectId!, projectSettings);
      }
    }

    await _persistAndSync(
      _bump(board!.copyWith(columns: _normalizeOrders(inserted))),
    );
    if (fromColumnId != toColumnId) {
      final originalIndex = moving!.order;
      if (!_applyingAutomation) {
        _pushUndo(
          '移动「${moving!.title}」',
          () => moveCard(
            cardId: cardId,
            fromColumnId: toColumnId,
            toColumnId: fromColumnId,
            toDisplayIndex: originalIndex,
          ),
          redo: () => moveCard(
            cardId: cardId,
            fromColumnId: fromColumnId,
            toColumnId: toColumnId,
            toDisplayIndex: toDisplayIndex,
            completed: completed,
            completedAt: completedAt,
          ),
        );
      }
      await _recordActivity(
        entityId: cardId,
        entityTitle: moving!.title,
        action: ActivityAction.moved,
        details: {
          'fromColumnId': fromColumnId,
          'toColumnId': toColumnId,
        },
      );
      if (!_applyingAutomation) {
        final card = findCardById(cardId);
        if (card != null) {
          await _runAutomations(
            _automationEngine.effectsForMove(
              rules: projectSettings.automationRules,
              toColumnId: toColumnId,
              card: card,
            ),
            columnId: toColumnId,
            cardId: cardId,
          );
        }
      }
    }
    return null;
      });
  }

  Future<String?> restoreTrashItem(String trashItemId) async {
    return _withBoardMutation(() async {
    final labelIndex = labelTrash.indexWhere((item) => item.id == trashItemId);
    if (labelIndex >= 0) {
      return _restoreLabel(labelTrash[labelIndex]);
    }

    final appIndex =
        appTrash.items.indexWhere((item) => item.id == trashItemId);
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
      });
  }

  Future<void> permanentlyDeleteTrashItem(String trashItemId) async {
    return _withBoardMutation(() async {
    TrashItem? target;
    for (final item in allTrashItems) {
      if (item.id == trashItemId) {
        target = item;
        break;
      }
    }

    if (labelTrash.any((item) => item.id == trashItemId)) {
      labelTrash = labelTrash.where((item) => item.id != trashItemId).toList();
      await _persistLabelTrash();
      notifyListeners();
      return;
    }

    if (appTrash.items.any((item) => item.id == trashItemId)) {
      if (target != null) {
        await _deleteTrashItemAttachments(target);
      }
      appTrash = appTrash.bump().copyWith(
            items:
                appTrash.items.where((item) => item.id != trashItemId).toList(),
          );
      await _persistAppTrash();
      return;
    }

    for (final entry in projectTrashes.entries.toList()) {
      if (!entry.value.items.any((item) => item.id == trashItemId)) continue;
      if (target != null) {
        await _deleteTrashItemAttachments(target);
      }
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
      _markWorkspaceChanged();
      return;
    }
      });
  }

  Future<void> emptyTrash() async {
    return _withBoardMutation(() async {
    for (final item in allTrashItems) {
      await _deleteTrashItemAttachments(item);
    }

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
    _markWorkspaceChanged();
      });
  }

  Future<String?> _restoreLabel(TrashItem item) async {
    final label = item.labelPayload;
    if (label == null) return '数据损坏，无法还原';

    if (appSettings.customLabels.any((l) => l.key == label.key)) {
      return '标签已存在';
    }

    await _persistSharedContent(
      sharedContent.copyWith(
        labels: [
          ...sharedContent.labels,
          SharedLabel(
            id: label.key,
            name: label.name,
            colorValue: label.colorValue,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ],
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
    projectThemeIds[payload.entry.id] = payload.settings.themeId;
    appTrash = appTrash.bump().copyWith(
          items: appTrash.items.where((i) => i.id != item.id).toList(),
        );
    await _repository.saveAppTrash(appTrash);
    notifyListeners();
    _markWorkspaceChanged();
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
    return _withBoardMutation(() async {
      await _repository.saveBoard(projectId, next);
      if (isActive) {
        board = next;
        await _updateManifestEntry(title: next.title);
      }
      notifyListeners();
      _markWorkspaceChanged();
    });
  }

  Future<void> _deleteTrashItemAttachments(TrashItem item) async {
    final store = attachmentStore;
    final projectId = item.projectId;
    if (store == null || projectId == null) return;

    final card = item.cardPayload;
    if (card != null) {
      await store.deleteAttachments(
        projectId: projectId,
        attachments: card.attachments,
      );
      return;
    }

    final column = item.columnPayload;
    if (column != null) {
      for (final columnCard in column.cards) {
        await store.deleteAttachments(
          projectId: projectId,
          attachments: columnCard.attachments,
        );
      }
      return;
    }

    final project = item.projectPayload;
    if (project != null) {
      final ids = collectReferencedAttachmentIds(
        project.board,
        project.projectTrash,
        settings: project.settings,
      );
      for (final id in ids) {
        await store.deleteAttachment(projectId: projectId, attachmentId: id);
      }
    }
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
    _markWorkspaceChanged();
  }

  Future<void> saveWebDavConfig(WebDavConfig config) async {
    final connected = config.enabled && config.isConfigured;
    await _withBoardMutation(() async {
      webDavConfig = config;
      await _repository.saveWebDavConfig(config);
      // 仅自动拉取开启时挂后台轮询；保存配置本身不触发同步
      if (connected && config.autoPull) {
        _syncService.startPolling();
      } else {
        _syncService.stopPolling();
      }
      notifyListeners();
    });
    unawaited(_syncService.refreshPendingUploadCount());
  }

  Future<bool> testWebDav(WebDavConfig config) {
    return _syncService.testConnection(config);
  }

  Future<void> syncNow() async {
    await _syncService.pullAndMerge(userInitiated: true);
    await _reloadUiAfterSync();
  }

  /// 取消进行中的 WebDAV 同步，恢复可继续操作
  bool cancelSync() {
    return _syncService.cancelSync();
  }

  /// 解决单卡冲突：保留主副本或另一侧
  Future<void> resolveCardConflict(
    String columnId,
    String cardId,
    CardConflictResolution resolution,
  ) async {
    return _withBoardMutation(() async {
    if (board == null) return;

    KanbanCard? target;
    String? targetColumnId;
    for (final col in board!.columns) {
      for (final card in col.cards) {
        if (card.id == cardId) {
          target = card;
          targetColumnId = col.id;
          break;
        }
      }
      if (target != null) break;
    }
    if (target == null || !target.hasConflict) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    late KanbanCard resolved;
    var resolvedColumnId = targetColumnId!;

    if (resolution == CardConflictResolution.keepPrimary) {
      if (target.conflictDeleted) {
        // note: 主侧是「仍存在」版本，选择主侧即保留卡片并清除删除冲突
        resolved = target.copyWith(clearConflict: true, updatedAt: now);
      } else {
        resolved = target.copyWith(clearConflict: true, updatedAt: now);
      }
    } else {
      if (target.conflictDeleted) {
        // 选择另一侧删除意图与普通删除一致，保留可恢复快照。
        await deleteCard(targetColumnId, cardId);
        return;
      }
      final other = target.conflictSide;
      if (other == null) return;
      resolved = other.copyWith(clearConflict: true, updatedAt: now);
      resolvedColumnId = target.conflictColumnId ?? targetColumnId;
    }

    var columns = board!.columns.map((col) {
      return col.copyWith(
        cards: col.cards.where((c) => c.id != cardId).toList(),
      );
    }).toList();

    columns = columns.map((col) {
      if (col.id != resolvedColumnId) return col;
      final cards = [...col.cards, resolved]
        ..sort((a, b) => a.order.compareTo(b.order));
      return col.copyWith(cards: cards);
    }).toList();

    // 若目标列不存在，放回原列
    if (!columns.any((c) => c.id == resolvedColumnId)) {
      columns = columns.map((col) {
        if (col.id != targetColumnId) return col;
        return col.copyWith(cards: [...col.cards, resolved]);
      }).toList();
    }

    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
      });
  }

  Future<void> resolveSettingsConflict({required bool keepPrimary}) async {
    return _withBoardMutation(() async {
    if (!projectSettings.hasConflict) return;
    final next = keepPrimary
        ? projectSettings.copyWith(clearConflictSide: true)
        : (projectSettings.conflictSide ?? projectSettings)
            .copyWith(clearConflictSide: true);
    await _persistProjectSettings(next.bump());
      });
  }

  /// 解决当前看板的标题冲突。
  Future<void> resolveBoardTitleConflict({required bool keepPrimary}) async {
    return _withBoardMutation(() async {
    final current = board;
    if (current == null || current.conflictTitle == null) return;
    final title = keepPrimary ? current.title : current.conflictTitle!;
    await _persistAndSync(
      _bump(
        current.copyWith(
          title: title,
          clearConflictTitle: true,
        ),
      ),
    );
      });
  }

  /// 解决项目清单条目的标题冲突。
  Future<void> resolveProjectTitleConflict(
    String projectId, {
    required bool keepPrimary,
  }) async {
    return _withBoardMutation(() async {
    final entry = manifest?.findById(projectId);
    if (entry == null || entry.conflictTitle == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final title = keepPrimary ? entry.title : entry.conflictTitle!;
    final projects = manifest!.projects.map((project) {
      if (project.id != projectId) return project;
      return project.copyWith(
        title: title,
        updatedAt: now,
        revision: project.revision + 1,
        clearConflictTitle: true,
      );
    }).toList();
    manifest = manifest!.bump().copyWith(projects: projects);
    await _repository.saveManifest(manifest!);
    notifyListeners();
    _markWorkspaceChanged();
      });
  }

  /// 解决项目删改冲突：保留项目或确认删除
  Future<void> resolveProjectConflict(
    String projectId, {
    required bool keepProject,
  }) async {
    return _withBoardMutation(() async {
    if (manifest == null) return;
    final entry = manifest!.findById(projectId);
    if (entry == null || !entry.conflictDeleted) return;

    if (!keepProject) {
      await deleteProject(projectId);
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final projects = manifest!.projects.map((p) {
      if (p.id != projectId) return p;
      return p.copyWith(
        clearConflict: true,
        updatedAt: now,
        revision: p.revision + 1,
      );
    }).toList();
    manifest = manifest!.bump().copyWith(projects: projects);
    await _repository.saveManifest(manifest!);
    notifyListeners();
    _markWorkspaceChanged();
      });
  }

  @override
  void dispose() {
    _backupCoordinator.dispose();
    mcpHost.dispose();
    _syncService.dispose();
    super.dispose();
  }
}

class _ProjectMutationScope {
  _ProjectMutationScope({
    required this.projectId,
    required this.board,
    required this.settings,
    required this.trash,
  });

  final String projectId;
  KanbanBoard? board;
  ProjectSettings settings;
  TrashBin trash;
  bool pendingNotify = false;
  bool isActive = true;
}
