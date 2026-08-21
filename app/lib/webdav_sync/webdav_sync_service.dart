import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:webdav_client/webdav_client.dart';

import '../common/async_mutex.dart';
import '../features/attachments/attachment_sync_adapter.dart';
import '../features/attachments/attachment_sync_plan.dart';
import '../features/import_export/backup_archive_service.dart';
import '../features/import_export/backup_history_store.dart';
import '../features/wallpapers/wallpaper_archive_service.dart';
import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../features/shared_content/shared_content.dart';
import '../features/sync_conflict/sync_conflict.dart';
import '../features/trash/trash_models.dart';
import '../models/kanban_models.dart';
import '../storage/json_file_io.dart';
import '../storage/kanban_paths.dart';
import 'bounded_concurrency.dart';
import 'live_archive_marker.dart';
import 'sync_progress.dart';
import 'sync_index.dart';
import 'sync_upload_plan.dart';
import 'webdav_config.dart';

export '../features/sync_conflict/workspace_snapshot.dart';
export 'live_archive_marker.dart';
export 'sync_progress.dart';
export 'sync_index.dart';
export 'sync_upload_plan.dart';

part 'webdav_sync_scheduler.dart';
part 'webdav_sync_client_io.dart';
part 'webdav_sync_live_archive.dart';
part 'webdav_sync_attachments.dart';
part 'webdav_sync_push.dart';
part 'webdav_sync_pull.dart';
part 'webdav_sync_wallpaper_pack.dart';
part 'webdav_sync_backup.dart';

enum SyncStatus { idle, syncing, success, error }

const kDownloadWallpaperLibraryHint = 'Some wallpapers are missing locally; download the wallpaper library';

typedef BackupPackageCapture = Future<BackupPackage> Function();
typedef BackupPackageApply = Future<void> Function(BackupPackage package);
typedef WallpaperPackageCapture = Future<WallpaperArchivePackage> Function();
typedef WallpaperPackageApply = Future<void> Function(
  WallpaperArchivePackage package,
);

typedef WorkspaceTransactionRunner = Future<T> Function<T>(
  Future<T> Function() action,
);

Future<T> _runWorkspaceActionDirectly<T>(Future<T> Function() action) =>
    action();

/// 用户取消同步时抛出，用于协作式中止进行中的推送/拉取
class SyncCancelledException implements Exception {
  const SyncCancelledException();

  @override
  String toString() => 'SyncCancelledException';
}

/// 字段与核心状态宿主；mixin 的 `on` 约束指向此类，避免与公开类循环继承。
abstract class _WebDavSyncHost {
  _WebDavSyncHost({
    required Future<WebDavConfig> Function() loadConfig,
    required Future<ProjectWorkspaceSnapshot> Function() loadWorkspace,
    required Future<void> Function(ProjectWorkspaceSnapshot workspace)
        saveWorkspace,
    required SyncBaseStore syncBaseStore,
    required AttachmentSyncAdapter attachmentSync,
    required WorkspaceTransactionRunner runWorkspaceTransaction,
    BackupPackageCapture? captureBackupPackage,
    BackupPackageApply? applyBackupPackage,
    WallpaperPackageCapture? captureWallpaperPackage,
    WallpaperPackageApply? applyWallpaperPackage,
  })  : _loadConfig = loadConfig,
        _loadWorkspace = loadWorkspace,
        _saveWorkspace = saveWorkspace,
        _syncBaseStore = syncBaseStore,
        _attachmentSync = attachmentSync,
        _runWorkspaceTransaction = runWorkspaceTransaction,
        _captureBackupPackageFn = captureBackupPackage,
        _applyBackupPackageFn = applyBackupPackage,
        _captureWallpaperPackageFn = captureWallpaperPackage,
        _applyWallpaperPackageFn = applyWallpaperPackage;

  final Future<WebDavConfig> Function() _loadConfig;
  final Future<ProjectWorkspaceSnapshot> Function() _loadWorkspace;
  final Future<void> Function(ProjectWorkspaceSnapshot workspace)
      _saveWorkspace;
  final SyncBaseStore _syncBaseStore;
  final AttachmentSyncAdapter _attachmentSync;
  final AsyncMutex _backupMutex = AsyncMutex();
  final WorkspaceTransactionRunner _runWorkspaceTransaction;
  final BackupPackageCapture? _captureBackupPackageFn;
  final BackupPackageApply? _applyBackupPackageFn;
  final WallpaperPackageCapture? _captureWallpaperPackageFn;
  final WallpaperPackageApply? _applyWallpaperPackageFn;

  SyncStatus status = SyncStatus.idle;
  String? lastError;
  String? attachmentSyncWarning;
  DateTime? lastSyncedAt;
  SyncProgress? progress;

  /// 相对 SyncBase 是否还有未上传的工作区变更（0 或 1）
  int pendingUploadCount = 0;

  /// 最近一次附件上传失败的原始错误（用于提示细节）
  String? _lastAttachmentError;

  Timer? _cooldownRetryTimer;
  Timer? _pendingCountTimer;
  int _pendingCountGen = 0;
  bool _pushInFlight = false;
  bool _pushPending = false;
  bool _pushPendingForce = false;
  bool _syncInFlight = false;
  bool _pullPending = false;
  bool _pullPendingUserInitiated = false;
  bool _pullPendingReplace = false;

  /// 当前同步世代：每次开跑或取消时递增，用于丢弃已取消回合的结果
  int _syncRunId = 0;

  /// 用户已请求取消；I/O 检查点协作中止，不强制掐断底层 HTTP
  bool _cancelRequested = false;

  DateTime? _cooldownUntil;
  int _consecutiveFailures = 0;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  final _progressController = StreamController<SyncProgress?>.broadcast();
  Stream<SyncProgress?> get progressStream => _progressController.stream;

  final _pendingCountController = StreamController<int>.broadcast();
  Stream<int> get pendingUploadCountStream => _pendingCountController.stream;

  void _setProgress(SyncProgress? value) {
    progress = value;
    if (!_progressController.isClosed) {
      _progressController.add(value);
    }
  }

  void _clearProgress() => _setProgress(null);

  Future<T> _withLocalTransaction<T>(Future<T> Function() action) =>
      _runWorkspaceTransaction(action);

  Future<ProjectWorkspaceSnapshot> _captureWorkspace() =>
      _withLocalTransaction(_loadWorkspace);

  Future<BackupPackage> _captureBackupPackage() async {
    final capture = _captureBackupPackageFn;
    if (capture != null) return capture();
    return BackupPackage(workspace: await _loadWorkspace());
  }

  Future<void> _applySyncedBackupPackage(BackupPackage package) async {
    final apply = _applyBackupPackageFn;
    if (apply != null) {
      await apply(package);
      return;
    }
    await _saveWorkspace(package.workspace);
  }

  Future<WallpaperArchivePackage> _captureWallpaperPackage() async {
    final capture = _captureWallpaperPackageFn;
    if (capture != null) return capture();
    return const WallpaperArchivePackage(assets: []);
  }

  Future<void> _applySyncedWallpaperPackage(
    WallpaperArchivePackage package,
  ) async {
    final apply = _applyWallpaperPackageFn;
    if (apply != null) {
      await apply(package);
      return;
    }
  }

  void _setStatus(SyncStatus value, {String? error}) {
    status = value;
    lastError = error;
    if (value == SyncStatus.success) {
      lastSyncedAt = DateTime.now();
    }
    _statusController.add(value);
  }

  bool _workspaceJsonEquals(
    ProjectWorkspaceSnapshot a,
    ProjectWorkspaceSnapshot b,
  ) {
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  }

  /// 由 push mixin 实现；调度器等跨职责调用走此抽象入口。
  Future<void> _pushNow({
    bool force = false,
    BackupPackage? package,
  });

  /// 由 pull mixin 实现；调度器等跨职责调用走此抽象入口。
  Future<void> _pullAndMerge({
    bool userInitiated = false,
    bool replaceLocal = false,
  });
}

/// 手动 WebDAV 同步：上传覆盖云端、下载覆盖本机、三路合并
class WebDavSyncService extends _WebDavSyncHost
    with
        _WebDavSyncScheduler,
        _WebDavSyncClientIo,
        _WebDavSyncLiveArchive,
        _WebDavSyncAttachments,
        _WebDavSyncPush,
        _WebDavSyncPull,
        _WebDavSyncWallpaperPack,
        _WebDavSyncBackup {
  WebDavSyncService({
    required super.loadConfig,
    required super.loadWorkspace,
    required super.saveWorkspace,
    required super.syncBaseStore,
    AttachmentSyncAdapter? attachmentSync,
    WorkspaceTransactionRunner? runWorkspaceTransaction,
    super.captureBackupPackage,
    super.applyBackupPackage,
    super.captureWallpaperPackage,
    super.applyWallpaperPackage,
  }) : super(
          attachmentSync: attachmentSync ?? AttachmentSyncAdapter(null),
          runWorkspaceTransaction:
              runWorkspaceTransaction ?? _runWorkspaceActionDirectly,
        );

  /// 推送本地工作区为固定名压缩包，覆盖云端。
  ///
  /// [package]：若已持有待推快照（例如刚合并的结果），可直接传入以免重复捕获。
  Future<void> pushNow({
    bool force = false,
    ProjectWorkspaceSnapshot? workspace,
    ProjectWorkspaceSnapshot? baseline,
    BackupPackage? package,
  }) {
    return _pushNow(
      force: force,
      package: package,
    );
  }

  Future<void> pullAndMerge({bool userInitiated = false}) {
    return _pullAndMerge(userInitiated: userInitiated);
  }

  /// 全量拉取云端并覆盖本机，不合并、不回推。
  Future<void> pullAndReplace() {
    return _pullAndMerge(userInitiated: true, replaceLocal: true);
  }

  Future<void> uploadWallpapersNow() => _pushWallpaperPack();

  Future<void> downloadWallpapersNow() => _pullWallpaperPack();

  void dispose() {
    _cooldownRetryTimer?.cancel();
    _pendingCountTimer?.cancel();
    stopPolling();
    _statusController.close();
    _progressController.close();
    _pendingCountController.close();
  }
}
