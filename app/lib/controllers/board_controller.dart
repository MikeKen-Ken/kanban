import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../common/async_mutex.dart';
import '../common/git_commit_ref.dart';
import '../features/attachments/attachment_missing.dart';
import '../features/attachments/attachment_refs.dart';
import '../features/attachments/attachment_store.dart';
import '../features/attachments/attachment_sync_adapter.dart';
import '../features/attachments/card_image_picker.dart';
import '../features/attachments/card_file_opener.dart' as card_file_opener;
import '../features/attachments/card_file_picker.dart';
import '../features/attachments/picked_file_bytes.dart';
import '../features/activity/activity_models.dart';
import '../features/android_widget/android_widget.dart';
import '../features/automations/automations.dart';
import '../features/completed_auto_clear/completed_auto_clear.dart';
import '../features/import_export/backup_archive_service.dart';
import '../features/import_export/backup_coordinator.dart';
import '../features/import_export/backup_history_store.dart';
import '../features/import_export/backup_restore_service.dart';
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
import '../features/wallpapers/wallpaper_archive_service.dart';
import '../features/wallpapers/wallpaper_models.dart';
import '../models/kanban_models.dart';
import '../features/kanban/column_card_preferences.dart';
import '../features/kanban/kanban_labels.dart';
import '../features/kanban/move_to_rework_on_new_feedback.dart';
import '../features/kanban/need_resource_column_gate.dart';
import '../features/kanban/transfer_card.dart';
import '../features/kanban/verify_column.dart';
import '../features/trash/trash_models.dart';
import '../features/trash/trash_auto_clear.dart';
import '../settings/app_settings.dart';
import '../storage/board_storage.dart';
import '../webdav_sync/webdav_config.dart';
import '../webdav_sync/webdav_sync_service.dart';

part 'board_controller_lifecycle.dart';
part 'board_controller_mutation.dart';
part 'board_controller_persist.dart';
part 'board_controller_projects.dart';
part 'board_controller_cards.dart';
part 'board_controller_moves.dart';
part 'board_controller_attachments.dart';
part 'board_controller_file_attachments.dart';
part 'board_controller_trash.dart';
part 'board_controller_sync.dart';
part 'board_controller_scope.dart';
part 'board_controller_wallpapers.dart';
part 'board_controller_android_widget.dart';

enum CardConflictResolution { keepPrimary, keepOther }

final Object _projectMutationScopeKey = Object();

/// 设置页启用提醒后的结果，用于给用户准确反馈。
enum NotificationPermissionResult {
  enabled,
  denied,
  openedSystemSettings,
}

/// mixin 挂载基类：避免 `on BoardController` 自引用在循环 import 下导致对外成员丢失。
abstract class _BoardControllerBase extends ChangeNotifier {
  _BoardControllerBase({
    required BoardRepository repository,
    required WebDavSyncService syncService,
    required BackupHistoryStore backupHistoryStore,
  })  : _repository = repository,
        _syncService = syncService,
        _backupHistoryStore = backupHistoryStore;

  final BoardRepository _repository;
  final WebDavSyncService _syncService;
  final BackupHistoryStore _backupHistoryStore;
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

  /// 回收站自动清理：上次扫描时间（进程内节流）
  DateTime? _lastTrashAutoClearAt;
  bool _trashAutoClearRunning = false;

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

  /// 当前项目已缓存到本地、可实际渲染的壁纸 id。
  List<String> displayableWallpaperIds = const [];
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
}

class BoardController extends _BoardControllerBase {
  BoardController._({
    required super.repository,
    required super.syncService,
    required BackupHistoryStore backupHistoryStore,
  }) : super(
          backupHistoryStore: backupHistoryStore,
        ) {
    _backupHistorySupported = backupHistoryStore.isSupported;
    _backupCoordinator = BackupCoordinator(
      localStore: backupHistoryStore,
      createArchive: createBackupArchive,
      writeRemote: _syncService.writeBackupSnapshot,
      listRemote: _syncService.listRemoteBackupSnapshots,
      pruneRemote: _syncService.deleteRemoteBackupsOlderThan,
    );
  }

  late final KanbanMcpHost mcpHost = KanbanMcpHost(this);

  /// 后台项目作用域内推迟通知，避免污染 UI 当前项目监听方。
  @override
  void notifyListeners() {
    final scope = _projectMutationScope;
    if (scope != null) {
      scope.pendingNotify = true;
      return;
    }
    super.notifyListeners();
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
      captureBackupPackage: () => controller.captureBackupPackage(),
      applyBackupPackage: (package) => controller._applyBackupPackage(package),
      captureWallpaperPackage: () => controller.captureWallpaperPackage(),
      applyWallpaperPackage: (package) =>
          controller.applyWallpaperPackage(package),
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
  void dispose() {
    _backupCoordinator.dispose();
    mcpHost.dispose();
    _syncService.dispose();
    super.dispose();
  }
}
