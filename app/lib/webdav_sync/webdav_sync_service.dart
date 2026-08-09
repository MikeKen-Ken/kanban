import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:webdav_client/webdav_client.dart';

import '../common/async_mutex.dart';
import '../features/attachments/attachment_sync_adapter.dart';
import '../features/attachments/attachment_sync_plan.dart';
import '../features/import_export/backup_history_store.dart';
import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../features/shared_content/shared_content.dart';
import '../features/sync_conflict/sync_conflict.dart';
import '../features/trash/trash_models.dart';
import '../models/kanban_models.dart';
import '../storage/json_file_io.dart';
import '../storage/kanban_paths.dart';
import 'sync_progress.dart';
import 'sync_index.dart';
import 'sync_upload_plan.dart';
import 'webdav_config.dart';

export '../features/sync_conflict/workspace_snapshot.dart';
export 'sync_progress.dart';
export 'sync_index.dart';
export 'sync_upload_plan.dart';

enum SyncStatus { idle, syncing, success, error }

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

/// 自动 WebDAV 同步：本地变更后防抖上传，启动/轮询时拉取合并
class WebDavSyncService {
  WebDavSyncService({
    required Future<WebDavConfig> Function() loadConfig,
    required Future<ProjectWorkspaceSnapshot> Function() loadWorkspace,
    required Future<void> Function(ProjectWorkspaceSnapshot workspace)
        saveWorkspace,
    required SyncBaseStore syncBaseStore,
    AttachmentSyncAdapter? attachmentSync,
    WorkspaceTransactionRunner? runWorkspaceTransaction,
  })  : _loadConfig = loadConfig,
        _loadWorkspace = loadWorkspace,
        _saveWorkspace = saveWorkspace,
        _syncBaseStore = syncBaseStore,
        _attachmentSync = attachmentSync ?? AttachmentSyncAdapter(null),
        _runWorkspaceTransaction =
            runWorkspaceTransaction ?? _runWorkspaceActionDirectly;

  final Future<WebDavConfig> Function() _loadConfig;
  final Future<ProjectWorkspaceSnapshot> Function() _loadWorkspace;
  final Future<void> Function(ProjectWorkspaceSnapshot workspace)
      _saveWorkspace;
  final SyncBaseStore _syncBaseStore;
  final AttachmentSyncAdapter _attachmentSync;
  final AsyncMutex _backupMutex = AsyncMutex();
  final WorkspaceTransactionRunner _runWorkspaceTransaction;

  SyncStatus status = SyncStatus.idle;
  String? lastError;
  String? attachmentSyncWarning;
  DateTime? lastSyncedAt;
  SyncProgress? progress;

  /// 相对 SyncBase 尚未上传的 JSON 文件数（跨全工作区）
  int pendingUploadCount = 0;

  /// 最近一次附件上传失败的原始错误（用于提示细节）
  String? _lastAttachmentError;

  Timer? _debounceTimer;
  Timer? _pollTimer;
  Timer? _cooldownRetryTimer;
  Timer? _pendingCountTimer;
  int _pushScheduleGen = 0;
  int _pendingCountGen = 0;
  bool _pollingEnabled = false;
  bool _pushInFlight = false;
  bool _pushPending = false;
  bool _pushPendingForce = false;
  bool _syncInFlight = false;
  bool _pullPending = false;
  bool _pullPendingUserInitiated = false;

  /// 当前同步世代：每次开跑或取消时递增，用于丢弃已取消回合的结果
  int _syncRunId = 0;

  /// 用户已请求取消；I/O 检查点协作中止，不强制掐断底层 HTTP
  bool _cancelRequested = false;

  /// 上次开始同步尝试的时间（成功/失败都更新，用于节流）
  DateTime? _lastAttemptAt;

  /// 限流/失败后的冷却截止时间
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

  Client? _client(WebDavConfig config) {
    if (!config.isConfigured) return null;
    var url = config.serverUrl.trim();
    if (!url.endsWith('/')) url = '$url/';
    final client = newClient(
      url,
      user: config.username.trim(),
      password: config.password,
      debug: false,
    );
    // note: 图片附件可能较大，放宽传输超时避免拉取被误判为失败
    client.setReceiveTimeout(120000);
    client.setSendTimeout(120000);
    return client;
  }

  bool _isRemoteNotFound(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('404') ||
        message.contains('not found') ||
        message.contains('no such file') ||
        message.contains('不存在');
  }

  Iterable<String> _directoryPathCandidates(String dir) sync* {
    yield dir;
    if (!dir.endsWith('/')) yield '$dir/';
  }

  Future<List<File>> _readDirWithFallback(Client client, String dir) async {
    _ensureNotCancelled();
    for (final path in _directoryPathCandidates(dir)) {
      _ensureNotCancelled();
      try {
        return await client.readDir(path);
      } catch (_) {
        continue;
      }
    }
    return const [];
  }

  String _remoteFilePath(String parentDir, File file) {
    final path = file.path?.trim();
    if (path != null && path.isNotEmpty) {
      final normalized = _normalizeRemotePath(path, parentDir);
      if (normalized != null) return normalized;
    }
    final name = file.name?.trim();
    if (name != null && name.isNotEmpty) {
      final prefix = parentDir.endsWith('/') ? parentDir : '$parentDir/';
      return '$prefix$name';
    }
    return parentDir;
  }

  /// 将 PROPFIND 返回的绝对 href（如 /dav/Koofr/KanbanApp/...）收成客户端相对路径
  String? _normalizeRemotePath(String path, String parentDir) {
    if (path.startsWith(parentDir)) return path;
    // note: Koofr 等会返回带挂载前缀的 href；截到与 parentDir 相同的后缀
    final marker = parentDir.startsWith('/') ? parentDir : '/$parentDir';
    final index = path.indexOf(marker);
    if (index >= 0) {
      return path.substring(index);
    }
    if (path.startsWith('/')) return path;
    final prefix = parentDir.endsWith('/') ? parentDir : '$parentDir/';
    return '$prefix$path';
  }

  Future<Set<String>> _listRemoteAttachmentNames(
    Client client,
    String attachmentsDir,
  ) async {
    final files = await _readDirWithFallback(client, attachmentsDir);
    final names = <String>{};
    for (final file in files) {
      if (file.isDir == true) continue;
      final name = file.name?.trim();
      if (name != null && name.isNotEmpty) {
        names.add(name);
        continue;
      }
      final path = file.path?.trim();
      if (path == null || path.isEmpty) continue;
      names.add(path.split('/').last);
    }
    return names;
  }

  String _remoteBase(WebDavConfig config) =>
      KanbanPaths.remoteBaseDir(config.remotePath);

  Future<void> _ensureParentDir(Client client, String remoteFilePath) async {
    final lastSlash = remoteFilePath.lastIndexOf('/');
    if (lastSlash <= 0) return;
    final dir = remoteFilePath.substring(0, lastSlash);
    try {
      await client.mkdirAll(dir);
    } catch (_) {
      // note: 目录已存在时忽略
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

  /// 取消进行中的同步（含排队中的 pull/push）；本地防抖推送定时器不受影响
  ///
  /// 返回是否确实发出了取消请求。底层传输为协作式中止，当前 HTTP 可能仍跑完，
  /// 但不会再提交成功/失败状态，并可立即再次触发同步。
  bool cancelSync() {
    final inFlight = _syncInFlight || _pushInFlight;
    final hasPending = _pullPending || _pushPending;
    if (status != SyncStatus.syncing && !inFlight && !hasPending) {
      return false;
    }

    _pullPending = false;
    _pullPendingUserInitiated = false;
    _pushPending = false;
    _pushPendingForce = false;

    if (inFlight) {
      _cancelRequested = true;
      _syncRunId++;
      print('已请求取消同步');
    } else {
      print('已取消排队中的同步');
    }

    if (status == SyncStatus.syncing) {
      _setStatus(SyncStatus.idle);
    }
    return true;
  }

  void _ensureNotCancelled([int? runId]) {
    if (_cancelRequested || (runId != null && runId != _syncRunId)) {
      throw const SyncCancelledException();
    }
  }

  bool _shouldCommit(int runId) =>
      !_cancelRequested && runId == _syncRunId;

  void _clearCancelFlag() {
    _cancelRequested = false;
  }

  bool _isRateLimitedError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('429') ||
        message.contains('toomanyrequests') ||
        message.contains('too many requests') ||
        message.contains('rate limit') ||
        message.contains('ratelimit');
  }

  int _pollIntervalSeconds(WebDavConfig config) =>
      WebDavConfig.clampPollIntervalSeconds(config.pollIntervalSeconds);

  Duration? _remainingCooldown([DateTime? now]) {
    final until = _cooldownUntil;
    if (until == null) return null;
    final remaining = until.difference(now ?? DateTime.now());
    if (remaining <= Duration.zero) return null;
    return remaining;
  }

  bool _canStartAutoSync(WebDavConfig config) {
    final now = DateTime.now();
    if (_remainingCooldown(now) != null) return false;
    final last = _lastAttemptAt;
    if (last == null) return true;
    return now.difference(last).inSeconds >= _pollIntervalSeconds(config);
  }

  void _noteAttempt() {
    _lastAttemptAt = DateTime.now();
  }

  void _noteSuccess() {
    _consecutiveFailures = 0;
    _cooldownUntil = null;
  }

  void _noteFailure(Object error) {
    _consecutiveFailures++;
    final rateLimited = _isRateLimitedError(error);
    // 限流从 60s 起跳；普通失败从 30s 起跳；指数退避，上限 10 分钟
    final baseSeconds = rateLimited ? 60 : 30;
    final shift = (_consecutiveFailures - 1).clamp(0, 4);
    final seconds = (baseSeconds * (1 << shift))
        .clamp(baseSeconds, WebDavConfig.maxPollIntervalSeconds);
    _cooldownUntil = DateTime.now().add(Duration(seconds: seconds));
  }

  bool _workspaceJsonEquals(
    ProjectWorkspaceSnapshot a,
    ProjectWorkspaceSnapshot b,
  ) {
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  }

  void _scheduleAfterCooldown(void Function() action) {
    final wait = _remainingCooldown() ?? Duration.zero;
    _cooldownRetryTimer?.cancel();
    _cooldownRetryTimer = Timer(wait, action);
  }

  void schedulePush() {
    final gen = ++_pushScheduleGen;
    _debounceTimer?.cancel();
    unawaited(_armPushDebounce(gen));
    schedulePendingUploadCountRefresh();
  }

  /// 本地变更后短防抖刷新待同步数量，避免与看板突变锁死锁
  void schedulePendingUploadCountRefresh() {
    final gen = ++_pendingCountGen;
    _pendingCountTimer?.cancel();
    _pendingCountTimer = Timer(const Duration(milliseconds: 200), () {
      if (gen != _pendingCountGen) return;
      unawaited(refreshPendingUploadCount());
    });
  }

  /// 相对 SyncBase 统计待上传 JSON 数；未配置同步时为 0
  Future<int> refreshPendingUploadCount() async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) {
      _setPendingUploadCount(0);
      return 0;
    }
    try {
      final workspace = await _captureWorkspace();
      final baseline = await _syncBaseStore.load();
      final count = countPendingSyncUploads(
        workspace: workspace,
        baseline: baseline,
      );
      _setPendingUploadCount(count);
    } on Object catch (e) {
      print('刷新待同步数量失败：$e');
    }
    return pendingUploadCount;
  }

  void _setPendingUploadCount(int value) {
    if (pendingUploadCount == value) return;
    pendingUploadCount = value;
    if (!_pendingCountController.isClosed) {
      _pendingCountController.add(value);
    }
  }

  Future<void> _armPushDebounce(int gen) async {
    final config = await _loadConfig();
    if (gen != _pushScheduleGen) return;

    final seconds = WebDavConfig.clampPushDebounceSeconds(
      config.pushDebounceSeconds,
    );
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(seconds: seconds), () {
      if (gen != _pushScheduleGen) return;
      final wait = _remainingCooldown();
      if (wait != null) {
        _scheduleAfterCooldown(() {
          unawaited(pushNow());
        });
        return;
      }
      unawaited(pushNow());
    });
  }

  Future<void> _writeJson(Client client, String path, Object data) async {
    _ensureNotCancelled();
    await _ensureParentDir(client, path);
    _ensureNotCancelled();
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );
    await client.write(path, bytes);
  }

  Future<Map<String, dynamic>?> _readJson(
    Client client,
    String path,
  ) async {
    _ensureNotCancelled();
    try {
      final data = await client.read(path);
      _ensureNotCancelled();
      final json = tryDecodeJsonBytes(data, path: path);
      if (json != null) return json;
      // note: 远端个别文件损坏时不拖垮整次同步；由调用方处理 null
      return null;
    } on SyncCancelledException {
      rethrow;
    } on Object catch (e) {
      if (_isRemoteNotFound(e)) {
        return null;
      }
      if (e is FormatException) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> _writeBytes(Client client, String path, Uint8List bytes) async {
    _ensureNotCancelled();
    await _ensureParentDir(client, path);
    // note: webdav_client.write() 会把字节拆成「每字节一个 chunk」的 Stream，
    // 截图 JPEG 体积稍大时极易超时；改走临时文件 + writeFromFile（按块流式上传）。
    final tmp = io.File(
      '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}'
      'kanban_webdav_${DateTime.now().microsecondsSinceEpoch}.bin',
    );
    try {
      _ensureNotCancelled();
      await tmp.writeAsBytes(bytes, flush: true);
      _ensureNotCancelled();
      await client.writeFromFile(tmp.path, path);
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {
        // note: 临时文件清理失败可忽略
      }
    }
  }

  Future<void> _writeBytesWithRetry(
    Client client,
    String path,
    Uint8List bytes,
  ) async {
    try {
      await _writeBytes(client, path, bytes);
    } on SyncCancelledException {
      rethrow;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _ensureNotCancelled();
      await _writeBytes(client, path, bytes);
    }
  }

  Future<Uint8List?> _readBytes(Client client, String path) async {
    _ensureNotCancelled();
    try {
      final data = await client.read(path);
      _ensureNotCancelled();
      return Uint8List.fromList(data);
    } on SyncCancelledException {
      rethrow;
    } on Object catch (e) {
      if (_isRemoteNotFound(e)) {
        return null;
      }
      rethrow;
    }
  }

  Future<bool> _downloadRemoteAttachment(
    Client client,
    String attachmentsDir,
    String base,
    String projectId,
    String attachmentId, {
    bool thumb = false,
  }) async {
    if (await _attachmentSync.exists(projectId, attachmentId, thumb: thumb)) {
      return true;
    }

    try {
      var bytes = await _readBytes(
        client,
        KanbanPaths.remoteProjectAttachmentPath(
          base,
          projectId,
          attachmentId,
          thumb: thumb,
        ),
      );
      if (bytes != null && bytes.isNotEmpty) {
        await _attachmentSync.writeFile(
          projectId,
          attachmentId,
          bytes,
          thumb: thumb,
        );
        return await _attachmentSync.exists(projectId, attachmentId,
            thumb: thumb);
      }

      final expectedName = KanbanPaths.remoteProjectAttachmentFileName(
        attachmentId,
        thumb: thumb,
      );
      final files = await _readDirWithFallback(client, attachmentsDir);
      for (final file in files) {
        if (file.isDir == true) continue;
        final name = file.name ?? file.path?.split('/').last ?? '';
        if (name != expectedName) continue;
        final remotePath = _remoteFilePath(attachmentsDir, file);
        bytes = await _readBytes(client, remotePath);
        if (bytes == null || bytes.isEmpty) continue;
        await _attachmentSync.writeFile(
          projectId,
          attachmentId,
          bytes,
          thumb: thumb,
        );
        if (await _attachmentSync.exists(projectId, attachmentId,
            thumb: thumb)) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }

    return await _attachmentSync.exists(projectId, attachmentId, thumb: thumb);
  }

  Future<int> _pushProjectAttachments(
    Client client,
    String base,
    String projectId,
    KanbanBoard board,
    TrashBin trash, {
    ProjectSettings? settings,
    bool cleanupOrphans = true,
  }) async {
    if (!_attachmentSync.isAvailable) return 0;

    var failed = 0;
    final keepIds =
        _attachmentSync.referencedIds(board, trash, settings: settings);
    final attachmentsDir =
        KanbanPaths.remoteProjectAttachmentsDir(base, projectId);
    final remoteNames =
        await _listRemoteAttachmentNames(client, attachmentsDir);

    for (final id in keepIds) {
      _ensureNotCancelled();
      for (final thumb in const [false, true]) {
        final localExists = await _attachmentSync.exists(
          projectId,
          id,
          thumb: thumb,
        );
        final remoteName = KanbanPaths.remoteProjectAttachmentFileName(
          id,
          thumb: thumb,
        );
        final remoteExists = remoteNames.contains(remoteName);
        if (!shouldUploadAttachmentFile(
          localExists: localExists,
          remoteExists: remoteExists,
        )) {
          continue;
        }
        final bytes = await _attachmentSync.readFile(
          projectId,
          id,
          thumb: thumb,
        );
        if (bytes == null) {
          if (!thumb) failed++;
          continue;
        }
        try {
          await _writeBytesWithRetry(
            client,
            KanbanPaths.remoteProjectAttachmentPath(
              base,
              projectId,
              id,
              thumb: thumb,
            ),
            bytes,
          );
          remoteNames.add(remoteName);
        } catch (e) {
          if (!thumb) {
            failed++;
            _lastAttachmentError ??= e.toString();
            // ignore: avoid_print
            print('附件上传失败 $projectId/$id: $e');
          }
        }
      }
    }

    if (cleanupOrphans) {
      try {
        await _cleanupRemoteAttachments(client, attachmentsDir, keepIds);
      } catch (_) {
        // note: 远端孤儿清理失败不影响已上传附件
      }
      try {
        await _attachmentSync.deleteOrphans(projectId, keepIds);
      } catch (_) {
        // note: 本地孤儿清理失败不影响同步结果
      }
    }
    return failed;
  }

  Future<int> _pullProjectAttachments(
    Client client,
    String base,
    String projectId,
    KanbanBoard board,
    TrashBin trash, {
    ProjectSettings? settings,
  }) async {
    if (!_attachmentSync.isAvailable) return 0;

    var failed = 0;
    final keepIds =
        _attachmentSync.referencedIds(board, trash, settings: settings);
    final attachmentsDir =
        KanbanPaths.remoteProjectAttachmentsDir(base, projectId);
    for (final id in keepIds) {
      _ensureNotCancelled();
      for (final thumb in const [false, true]) {
        await _downloadRemoteAttachment(
          client,
          attachmentsDir,
          base,
          projectId,
          id,
          thumb: thumb,
        );
      }
      if (!await _attachmentSync.exists(projectId, id)) {
        failed++;
      }
    }

    try {
      await _attachmentSync.deleteOrphans(projectId, keepIds);
    } catch (_) {
      // note: 本地孤儿清理失败不影响同步结果
    }
    return failed;
  }

  Future<void> _cleanupRemoteAttachments(
    Client client,
    String attachmentsDir,
    Set<String> keepIds,
  ) async {
    final files = await _readDirWithFallback(client, attachmentsDir);
    for (final file in files) {
      if (file.isDir == true) continue;
      final name = file.name ?? file.path?.split('/').last ?? '';
      final id = KanbanPaths.attachmentIdFromRemoteFileName(name);
      if (id == null || keepIds.contains(id)) continue;
      try {
        await client.remove(_remoteFilePath(attachmentsDir, file));
      } catch (_) {
        // note: 单个远端孤儿删除失败时继续
      }
    }
  }

  String _remotePathForUploadItem(String base, SyncUploadItem item) {
    switch (item.kind) {
      case SyncUploadKind.projectsManifest:
        return KanbanPaths.remoteProjectsPath(base);
      case SyncUploadKind.appTrash:
        return KanbanPaths.remoteAppTrashPath(base);
      case SyncUploadKind.sharedContent:
        return KanbanPaths.remoteSharedContentPath(base);
      case SyncUploadKind.boardMetadata:
        return KanbanPaths.remoteProjectBoardPath(base, item.projectId!);
      case SyncUploadKind.column:
        return KanbanPaths.remoteProjectColumnPath(
          base,
          item.projectId!,
          item.columnId!,
        );
      case SyncUploadKind.settings:
        return KanbanPaths.remoteProjectSettingsPath(base, item.projectId!);
      case SyncUploadKind.trash:
        return KanbanPaths.remoteProjectTrashPath(base, item.projectId!);
    }
  }

  Future<void> _ensureProjectDir(
    Client client,
    String base,
    String projectId,
    Set<String> ensured,
  ) async {
    if (!ensured.add(projectId)) return;
    try {
      await client.mkdirAll(KanbanPaths.remoteProjectDir(base, projectId));
    } catch (_) {
      // note: 目录已存在时忽略
    }
  }

  /// 按计划增量上传 JSON；[baseline] 为 null 时全量上传。
  Future<int> _pushWorkspaceJson({
    required Client client,
    required String base,
    required ProjectWorkspaceSnapshot workspace,
    ProjectWorkspaceSnapshot? baseline,
    required int runId,
  }) async {
    final plan = buildSyncUploadPlan(
      workspace: workspace,
      baseline: baseline,
    );
    final ensuredDirs = <String>{};
    final total = plan.items.length;
    var completed = 0;
    _setProgress(
      SyncProgress(
        phase: SyncPhase.uploading,
        completed: 0,
        total: total,
        skipped: plan.skippedFileCount,
        currentLabel: plan.isEmpty ? '无需上传 JSON' : null,
      ),
    );

    // note: 先写列文件、再写 board 元数据；计划内保持列项先于同项目 board
    final ordered = [...plan.items]..sort((a, b) {
        final aCol = a.kind == SyncUploadKind.column ? 0 : 1;
        final bCol = b.kind == SyncUploadKind.column ? 0 : 1;
        if (aCol != bCol) return aCol - bCol;
        return 0;
      });

    for (final item in ordered) {
      _ensureNotCancelled(runId);
      _setProgress(
        SyncProgress(
          phase: SyncPhase.uploading,
          completed: completed,
          total: total,
          skipped: plan.skippedFileCount,
          currentLabel: item.label,
        ),
      );
      final projectId = item.projectId;
      if (projectId != null) {
        await _ensureProjectDir(client, base, projectId, ensuredDirs);
      }
      await _writeJson(
        client,
        _remotePathForUploadItem(base, item),
        item.json,
      );
      completed++;
      _setProgress(
        SyncProgress(
          phase: SyncPhase.uploading,
          completed: completed,
          total: total,
          skipped: plan.skippedFileCount,
          currentLabel: item.label,
        ),
      );
    }

    for (final projectId in plan.projectsNeedingColumnCleanup) {
      _ensureNotCancelled(runId);
      final keep = plan.keepColumnIdsByProject[projectId] ?? const <String>{};
      await _cleanupRemoteColumns(
        client,
        KanbanPaths.remoteProjectColumnsDir(base, projectId),
        keep,
      );
    }

    if (plan.needsProjectCleanup) {
      _ensureNotCancelled(runId);
      await _cleanupRemoteProjects(
        client,
        KanbanPaths.remoteProjectsDir(base),
        plan.keepProjectIds,
      );
    }

    // 无论是否有 JSON 变更，都重写索引，便于旧远端补齐与拉取跳过
    _ensureNotCancelled(runId);
    await _writeSyncIndex(client, base, workspace);

    return plan.skippedFileCount;
  }

  Future<void> _writeSyncIndex(
    Client client,
    String base,
    ProjectWorkspaceSnapshot workspace,
  ) async {
    final index = buildSyncIndex(workspace);
    await _writeJson(
      client,
      KanbanPaths.remoteSyncIndexPath(base),
      index.toJson(),
    );
  }

  Future<SyncIndex?> _readSyncIndex(Client client, String base) async {
    final json = await _readJson(client, KanbanPaths.remoteSyncIndexPath(base));
    if (json == null) return null;
    final index = SyncIndex.fromJson(json);
    if (!index.isSupportedSchema) return null;
    return index;
  }

  Future<int> _pushAllProjectAttachments({
    required Client client,
    required String base,
    required ProjectWorkspaceSnapshot workspace,
    required int runId,
    bool cleanupOrphans = true,
  }) async {
    var attachmentFailures = 0;
    final projects = workspace.manifest.projects;
    var index = 0;
    for (final entry in projects) {
      _ensureNotCancelled(runId);
      index++;
      final board = workspace.boards[entry.id];
      final settings = workspace.settings[entry.id];
      final trash = workspace.projectTrash[entry.id] ?? TrashBin.empty;
      if (board == null || settings == null) continue;
      _setProgress(
        SyncProgress(
          phase: SyncPhase.attachments,
          completed: index - 1,
          total: projects.length,
          currentLabel: entry.title.trim().isEmpty ? entry.id : entry.title,
        ),
      );
      attachmentFailures += await _pushProjectAttachments(
        client,
        base,
        entry.id,
        board,
        trash,
        settings: settings,
        cleanupOrphans: cleanupOrphans,
      );
    }
    return attachmentFailures;
  }

  void _applyAttachmentSyncWarning(int failedCount) {
    if (failedCount > 0) {
      final detail = _lastAttachmentError;
      attachmentSyncWarning = (detail == null || detail.isEmpty)
          ? '$failedCount 个图片附件同步失败，可点击同步图标重试'
          : '$failedCount 个图片附件同步失败：$detail';
    } else {
      attachmentSyncWarning = null;
      _lastAttachmentError = null;
    }
  }

  /// 推送本地工作区。网络 I/O 不持有工作区事务锁。
  ///
  /// [baseline]：相对此快照跳过未变更 JSON；省略时自动使用 SyncBase。
  /// [workspace]：若已持有待推快照（例如刚合并的结果），可直接传入以免重复捕获。
  Future<void> pushNow({
    bool force = false,
    ProjectWorkspaceSnapshot? workspace,
    ProjectWorkspaceSnapshot? baseline,
  }) {
    return _pushNow(
      force: force,
      workspace: workspace,
      baseline: baseline,
    );
  }

  Future<void> _pushNow({
    bool force = false,
    ProjectWorkspaceSnapshot? workspace,
    ProjectWorkspaceSnapshot? baseline,
  }) async {
    if (_syncInFlight) {
      _pushPending = true;
      _pushPendingForce = force || _pushPendingForce;
      return;
    }
    if (_pushInFlight) {
      _pushPending = true;
      _pushPendingForce = force || _pushPendingForce;
      return;
    }
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;
    if (!force && !config.autoSync) return;

    // 非强制推送在冷却期内延后，避免限流风暴
    if (!force) {
      final wait = _remainingCooldown();
      if (wait != null) {
        _scheduleAfterCooldown(() {
          unawaited(pushNow(force: force));
        });
        return;
      }
    }

    final client = _client(config);
    if (client == null) return;

    // 用户刚取消时勿清标志开跑（例如 pull 交接 push 之间的窗口）
    if (_cancelRequested) {
      print('跳过推送：同步已取消');
      _clearCancelFlag();
      return;
    }

    final runId = _syncRunId;
    _pushInFlight = true;
    _noteAttempt();
    _setStatus(SyncStatus.syncing);
    _lastAttachmentError = null;
    _setProgress(const SyncProgress(phase: SyncPhase.discovering));

    try {
      _ensureNotCancelled(runId);
      final captured = workspace ?? await _captureWorkspace();
      final uploadBaseline =
          baseline ?? (workspace == null ? await _syncBaseStore.load() : null);
      final base = _remoteBase(config);

      final skipped = await _pushWorkspaceJson(
        client: client,
        base: base,
        workspace: captured,
        baseline: uploadBaseline,
        runId: runId,
      );
      print('增量推送：跳过 $skipped 个未变更 JSON 文件');

      _ensureNotCancelled(runId);
      final attachmentFailures = await _pushAllProjectAttachments(
        client: client,
        base: base,
        workspace: captured,
        runId: runId,
      );

      if (!_shouldCommit(runId)) {
        throw const SyncCancelledException();
      }

      _setProgress(const SyncProgress(phase: SyncPhase.finalizing));
      // 仅当本机工作区仍与已上传快照一致时推进 SyncBase，避免覆盖同步期间的新本地写入。
      await _withLocalTransaction(() async {
        final latest = await _loadWorkspace();
        if (_workspaceJsonEquals(latest, captured)) {
          await _syncBaseStore.save(captured);
        } else {
          print('推送后本地已有新变更，保留 SyncBase 并排队再次推送');
          _pushPending = true;
          _pushPendingForce = _pushPendingForce || force;
        }
      });

      _applyAttachmentSyncWarning(attachmentFailures);
      _noteSuccess();
      _setStatus(SyncStatus.success);
      unawaited(refreshPendingUploadCount());
    } on SyncCancelledException {
      print('推送同步已中止');
      if (status == SyncStatus.syncing) {
        _setStatus(SyncStatus.idle);
      }
      unawaited(refreshPendingUploadCount());
    } catch (e) {
      if (!_shouldCommit(runId)) {
        print('推送同步已取消，忽略错误：$e');
        unawaited(refreshPendingUploadCount());
      } else {
        _noteFailure(e);
        _setStatus(SyncStatus.error, error: e.toString());
        unawaited(refreshPendingUploadCount());
      }
    } finally {
      _pushInFlight = false;
      _clearProgress();
      if (_cancelRequested) {
        _clearCancelFlag();
      }
      _drainPendingWork(forceFallback: force);
    }
  }

  Future<void> _cleanupRemoteColumns(
    Client client,
    String columnsDir,
    Set<String> keepIds,
  ) async {
    try {
      final files = await client.readDir(columnsDir);
      for (final file in files) {
        final id = KanbanPaths.columnIdFromRemoteFile(file.path ?? '');
        if (id == null || keepIds.contains(id)) continue;
        await client.remove(file.path!);
      }
    } catch (_) {
      // note: 远端 columns 目录不存在时忽略
    }
  }

  Future<void> _cleanupRemoteProjects(
    Client client,
    String projectsDir,
    Set<String> keepIds,
  ) async {
    try {
      final dirs = await client.readDir(projectsDir);
      for (final entry in dirs) {
        final name = (entry.path ?? '').split('/').last;
        if (name.isEmpty || keepIds.contains(name)) continue;
        await client.remove(entry.path!);
      }
    } catch (_) {
      // note: 远端 projects 目录不存在时忽略
    }
  }

  Future<KanbanBoard?> _pullLegacyBoard(Client client, String base) async {
    final boardPath = KanbanPaths.remoteBoardPath(base);
    final meta = await _readJson(client, boardPath);
    if (meta == null) return null;

    if (KanbanBoard.isLegacyMonolithic(meta)) {
      return KanbanBoard.fromJson(meta);
    }

    final refs =
        (meta['columns'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final columns = <KanbanColumn>[];
    for (final ref in refs) {
      final id = ref['id'] as String;
      final colJson = await _readJson(
        client,
        KanbanPaths.remoteColumnPath(base, id),
      );
      if (colJson != null) {
        columns.add(KanbanColumn.fromJson(colJson));
      }
    }
    return KanbanBoard.fromMetadataJson(meta, columns);
  }

  Future<ProjectWorkspaceSnapshot?> pullRemote({
    ProjectWorkspaceSnapshot? reuseFrom,
  }) async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return null;

    final client = _client(config);
    if (client == null) return null;

    final base = _remoteBase(config);
    final manifestPath = KanbanPaths.remoteProjectsPath(base);

    try {
      final remoteIndex = await _readSyncIndex(client, base);
      if (reuseFrom != null &&
          remoteIndex != null &&
          syncIndexMatchesWorkspace(remoteIndex, reuseFrom)) {
        print('拉取：远端 sync_index 与 SyncBase 一致，跳过全部 JSON 下载');
        _setProgress(
          SyncProgress(
            phase: SyncPhase.downloading,
            completed: 0,
            total: 0,
            skipped: remoteIndex.files.length,
            currentLabel: 'JSON 未变更',
          ),
        );
        return reuseFrom;
      }

      var skipped = 0;
      var downloaded = 0;

      Future<Map<String, dynamic>?> readRel(
        String absolutePath,
        String relativePath,
        Object? baseJson,
      ) async {
        final reuse = canReuseSyncBaseJson(
          remoteIndex: remoteIndex,
          relativePath: relativePath,
          baseJson: baseJson,
        );
        if (reuse) {
          skipped++;
          _setProgress(
            SyncProgress(
              phase: SyncPhase.downloading,
              completed: downloaded,
              skipped: skipped,
              currentLabel: relativePath,
            ),
          );
          if (baseJson is Map<String, dynamic>) {
            return Map<String, dynamic>.from(baseJson);
          }
          final encoded = jsonDecode(syncCanonicalJson(baseJson!));
          return Map<String, dynamic>.from(encoded as Map);
        }
        final json = await _readJson(client, absolutePath);
        downloaded++;
        _setProgress(
          SyncProgress(
            phase: SyncPhase.downloading,
            completed: downloaded,
            skipped: skipped,
            currentLabel: relativePath,
          ),
        );
        return json;
      }

      final manifestJson = await readRel(
        manifestPath,
        SyncIndexPaths.projects,
        reuseFrom?.manifest.toJson(),
      );

      // note: 兼容旧版 v2 单看板远端结构
      if (manifestJson == null) {
        final legacyBoard = await _pullLegacyBoard(client, base);
        if (legacyBoard == null) return null;

        final now = DateTime.now().millisecondsSinceEpoch;
        final entry = ProjectEntry(
          id: legacyBoard.id,
          title: legacyBoard.title,
          updatedAt: now,
          revision: 1,
        );
        return ProjectWorkspaceSnapshot(
          manifest: ProjectsManifest(
            projects: [entry],
            updatedAt: now,
            revision: 1,
          ),
          boards: {legacyBoard.id: legacyBoard},
          settings: {legacyBoard.id: const ProjectSettings()},
        );
      }

      final manifest = ProjectsManifest.fromJson(manifestJson);
      final boards = <String, KanbanBoard>{};
      final settings = <String, ProjectSettings>{};
      final projectTrash = <String, TrashBin>{};

      for (final entry in manifest.projects) {
        final projectId = entry.id;
        final baseBoard = reuseFrom?.boards[projectId];
        final boardMeta = await readRel(
          KanbanPaths.remoteProjectBoardPath(base, projectId),
          SyncIndexPaths.projectBoard(projectId),
          baseBoard?.toMetadataJson(),
        );
        if (boardMeta == null) continue;

        if (KanbanBoard.isLegacyMonolithic(boardMeta)) {
          boards[projectId] = KanbanBoard.fromJson(boardMeta);
        } else {
          final refs = (boardMeta['columns'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          final baseColumnsById = <String, KanbanColumn>{
            for (final column in baseBoard?.columns ?? const <KanbanColumn>[])
              column.id: column,
          };
          final columns = <KanbanColumn>[];
          for (final ref in refs) {
            final colId = ref['id'] as String;
            final colJson = await readRel(
              KanbanPaths.remoteProjectColumnPath(base, projectId, colId),
              SyncIndexPaths.projectColumn(projectId, colId),
              baseColumnsById[colId]?.toJson(),
            );
            if (colJson != null) {
              columns.add(KanbanColumn.fromJson(colJson));
            }
          }
          boards[projectId] = KanbanBoard.fromMetadataJson(boardMeta, columns);
        }

        final settingsJson = await readRel(
          KanbanPaths.remoteProjectSettingsPath(base, projectId),
          SyncIndexPaths.projectSettings(projectId),
          reuseFrom?.settings[projectId]?.toJson(),
        );
        settings[projectId] = settingsJson == null
            ? const ProjectSettings()
            : ProjectSettings.fromJson(settingsJson);

        final trashJson = await readRel(
          KanbanPaths.remoteProjectTrashPath(base, projectId),
          SyncIndexPaths.projectTrash(projectId),
          (reuseFrom?.projectTrash[projectId] ?? TrashBin.empty).toJson(),
        );
        projectTrash[projectId] =
            trashJson == null ? TrashBin.empty : TrashBin.fromJson(trashJson);
      }

      final appTrashJson = await readRel(
        KanbanPaths.remoteAppTrashPath(base),
        SyncIndexPaths.appTrash,
        reuseFrom?.appTrash.toJson(),
      );
      final appTrash = appTrashJson == null
          ? TrashBin.empty
          : TrashBin.fromJson(appTrashJson);

      final baseShared = reuseFrom?.sharedContent;
      final sharedContentJson = await readRel(
        KanbanPaths.remoteSharedContentPath(base),
        SyncIndexPaths.sharedContent,
        (baseShared == null || baseShared.isUninitialized)
            ? null
            : baseShared.toJson(),
      );
      final sharedContent = sharedContentJson == null
          ? SharedContent.empty
          : SharedContent.fromJson(sharedContentJson);

      if (skipped > 0) {
        print('拉取：跳过 $skipped 个未变更 JSON，下载 $downloaded 个');
      }

      return ProjectWorkspaceSnapshot(
        manifest: manifest,
        boards: boards,
        settings: settings,
        projectTrash: projectTrash,
        appTrash: appTrash,
        sharedContent: sharedContent,
      );
    } on SyncCancelledException {
      rethrow;
    } on Object catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('404') || message.contains('not found')) {
        return null;
      }
      _setStatus(SyncStatus.error, error: e.toString());
      rethrow;
    }
  }

  ProjectWorkspaceSnapshot _mergeWorkspaces(
    ProjectWorkspaceSnapshot local,
    ProjectWorkspaceSnapshot remote,
    ProjectWorkspaceSnapshot? base,
  ) {
    return mergeWorkspaces(local: local, remote: remote, base: base);
  }

  Future<void> pullAndMerge({bool userInitiated = false}) {
    return _pullAndMerge(userInitiated: userInitiated);
  }

  Future<void> _pullAndMerge({bool userInitiated = false}) async {
    if (_syncInFlight || _pushInFlight) {
      // 仅用户手动同步才排队；自动轮询重叠直接丢弃，避免失败后立即连环重试
      if (userInitiated) {
        _pullPending = true;
        _pullPendingUserInitiated = true;
      }
      return;
    }

    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;

    if (!userInitiated && !_canStartAutoSync(config)) {
      return;
    }

    // note: 手动同步不受自动节流/冷却限制，由用户主动触发

    if (_cancelRequested) {
      print('跳过拉取：同步已取消');
      _clearCancelFlag();
      return;
    }

    final runId = _syncRunId;
    _syncInFlight = true;
    _noteAttempt();
    _setStatus(SyncStatus.syncing);
    _lastAttachmentError = null;
    _setProgress(const SyncProgress(phase: SyncPhase.discovering));
    try {
      _ensureNotCancelled(runId);
      // 短事务捕获本地快照；网络拉取在锁外进行。
      var local = await _captureWorkspace();
      final syncBase = await _syncBaseStore.load();
      _setProgress(const SyncProgress(phase: SyncPhase.downloading));
      final remote = await pullRemote(reuseFrom: syncBase);
      _ensureNotCancelled(runId);
      if (remote == null) {
        // note: 远端为空时上传本地；先结束本回合再 push
        _syncInFlight = false;
        await pushNow(force: true, workspace: local, baseline: null);
        return;
      }

      _setProgress(const SyncProgress(phase: SyncPhase.merging));
      var merged = _mergeWorkspaces(local, remote, syncBase);
      _ensureNotCancelled(runId);

      // 合并落盘前重新捕获，避免网络期间的本地写入被旧快照覆盖。
      merged = await _withLocalTransaction(() async {
        final latest = await _loadWorkspace();
        final next = _workspaceJsonEquals(latest, local)
            ? merged
            : _mergeWorkspaces(latest, remote, syncBase);
        await _saveWorkspace(next);
        return next;
      });

      final client = _client(config);
      var attachmentFailures = 0;
      if (client != null) {
        final base = _remoteBase(config);
        final projects = merged.manifest.projects;
        var index = 0;
        for (final entry in projects) {
          _ensureNotCancelled(runId);
          index++;
          final board = merged.boards[entry.id];
          if (board == null) continue;
          final trash = merged.projectTrash[entry.id] ?? TrashBin.empty;
          final settings = merged.settings[entry.id];
          _setProgress(
            SyncProgress(
              phase: SyncPhase.attachments,
              completed: index - 1,
              total: projects.length,
              currentLabel: entry.title.trim().isEmpty ? entry.id : entry.title,
            ),
          );
          attachmentFailures += await _pullProjectAttachments(
            client,
            base,
            entry.id,
            board,
            trash,
            settings: settings,
          );
        }
      }

      _applyAttachmentSyncWarning(attachmentFailures);

      // note: 合并结果与远端一致时跳过 JSON 回推，但仍需补传本地有、远端缺的附件
      if (_workspaceJsonEquals(merged, remote)) {
        if (shouldReconcileAttachmentsWhenJsonEquals(
              jsonEquals: true,
              attachmentSyncAvailable: _attachmentSync.isAvailable,
            ) &&
            client != null) {
          final base = _remoteBase(config);
          attachmentFailures += await _pushAllProjectAttachments(
            client: client,
            base: base,
            workspace: merged,
            runId: runId,
            cleanupOrphans: false,
          );
          _applyAttachmentSyncWarning(attachmentFailures);
        }
        if (!_shouldCommit(runId)) {
          throw const SyncCancelledException();
        }
        await _syncBaseStore.save(merged);
        _noteSuccess();
        _setStatus(SyncStatus.success);
        unawaited(refreshPendingUploadCount());
        return;
      }

      // note: 合并后按相对远端的增量回推，避免把并集只留在本机
      _ensureNotCancelled(runId);
      _syncInFlight = false;
      await pushNow(
        force: true,
        workspace: merged,
        baseline: remote,
      );
    } on SyncCancelledException {
      print('拉取同步已中止');
      if (status == SyncStatus.syncing) {
        _setStatus(SyncStatus.idle);
      }
      unawaited(refreshPendingUploadCount());
    } catch (e) {
      if (!_shouldCommit(runId)) {
        print('拉取同步已取消，忽略错误：$e');
        unawaited(refreshPendingUploadCount());
      } else {
        _noteFailure(e);
        _setStatus(SyncStatus.error, error: e.toString());
        unawaited(refreshPendingUploadCount());
      }
    } finally {
      _syncInFlight = false;
      _clearProgress();
      if (_cancelRequested) {
        _clearCancelFlag();
      }
      _drainPendingWork();
    }
  }

  void _drainPendingWork({bool forceFallback = false}) {
    final pull = _pullPending;
    final pullUser = _pullPendingUserInitiated;
    final push = _pushPending;
    final pushForce = _pushPendingForce || forceFallback;
    _pullPending = false;
    _pullPendingUserInitiated = false;
    _pushPending = false;
    _pushPendingForce = false;

    if (!pull && !push) return;

    final wait = _remainingCooldown();
    void run() {
      if (pull) {
        unawaited(pullAndMerge(userInitiated: pullUser));
      } else if (push) {
        unawaited(pushNow(force: pushForce));
      }
    }

    // 手动同步排队立即执行；自动推送仍遵守冷却
    if (wait != null && !(pull && pullUser)) {
      _scheduleAfterCooldown(run);
      return;
    }
    Timer.run(run);
  }

  /// 将本地时间点备份镜像到 WebDAV；未启用 WebDAV 时仅保留本地副本。
  Future<void> writeBackupSnapshot(
    BackupSnapshotInfo snapshot,
    Uint8List bytes,
  ) {
    return _backupMutex.guard(() async {
      final config = await _loadConfig();
      if (!config.enabled || !config.isConfigured) return;
      final client = _client(config);
      if (client == null) return;
      final base = _remoteBase(config);
      final backupDir = KanbanPaths.remoteBackupDir(base, snapshot.id);
      final archivePath =
          KanbanPaths.remoteBackupArchivePath(base, snapshot.id);
      final markerPath = KanbanPaths.remoteBackupMarkerPath(base, snapshot.id);
      await client.mkdirAll(backupDir);
      try {
        await client.remove(markerPath);
      } catch (_) {
        // 不存在完成标记时继续上传。
      }
      final temporary = io.File(
        '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}'
        'kanban_backup_${snapshot.id}.bin',
      );
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await client.writeFromFile(temporary.path, archivePath);
        final checksum = sha256.convert(bytes).toString();
        final markerBytes = Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'id': snapshot.id,
              'createdAt': snapshot.createdAt.toUtc().toIso8601String(),
              'sizeBytes': bytes.length,
              'sha256': checksum,
            }),
          ),
        );
        // 完成标记最后写入；没有标记的中断上传不会出现在恢复列表。
        await client.write(markerPath, markerBytes);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
  }

  /// 列出远端时间点备份。
  ///
  /// 不占用 [_backupMutex]，避免上传/清理进行中时设置页永久等待列表。
  /// 未写完完成标记的目录会被跳过，与上传并发时结果仍安全。
  Future<List<BackupSnapshotInfo>> listRemoteBackupSnapshots() async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return const [];
    final client = _client(config);
    if (client == null) return const [];
    final directory = KanbanPaths.remoteBackupsDir(_remoteBase(config));
    final result = <BackupSnapshotInfo>[];
    List<File> entries;
    try {
      entries = await client.readDir(directory);
    } catch (error) {
      if (_isRemoteNotFound(error)) return const [];
      rethrow;
    }
    for (final file in entries) {
      if (file.isDir != true) continue;
      final name = file.name ?? file.path?.split('/').last ?? '';
      final id = name;
      if (!_isSafeBackupId(id)) continue;
      final timestamp = int.tryParse(id.split('-').first);
      if (timestamp == null) continue;
      try {
        final markerBytes = await client.read(
          KanbanPaths.remoteBackupMarkerPath(_remoteBase(config), id),
        );
        final marker = tryDecodeJsonBytes(markerBytes);
        if (marker == null || marker['id'] != id) continue;
        result.add(
          BackupSnapshotInfo(
            id: id,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              timestamp,
              isUtc: true,
            ),
            sizeBytes: (marker['sizeBytes'] as num?)?.toInt() ?? 0,
          ),
        );
      } catch (error) {
        if (_isRemoteNotFound(error)) continue;
        rethrow;
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<Uint8List?> readRemoteBackupSnapshot(String id) {
    return _backupMutex.guard(() async {
      if (!_isSafeBackupId(id)) throw const FormatException('备份标识无效');
      final config = await _loadConfig();
      if (!config.enabled || !config.isConfigured) return null;
      final client = _client(config);
      if (client == null) return null;
      final base = _remoteBase(config);
      final markerPath = KanbanPaths.remoteBackupMarkerPath(base, id);
      final markerBytes = await client.read(markerPath);
      final marker = tryDecodeJsonBytes(markerBytes);
      if (marker == null || marker['id'] != id) return null;
      final bytes = Uint8List.fromList(
        await client.read(KanbanPaths.remoteBackupArchivePath(base, id)),
      );
      final expectedSize = (marker['sizeBytes'] as num?)?.toInt();
      final expectedHash = marker['sha256'] as String?;
      if (expectedSize != bytes.length ||
          expectedHash == null ||
          sha256.convert(bytes).toString() != expectedHash) {
        try {
          await client.remove(markerPath);
        } catch (_) {
          // 移除失败时仍报告校验错误。
        }
        throw const FormatException('WebDAV 备份校验失败');
      }
      return bytes;
    });
  }

  Future<void> deleteRemoteBackupsOlderThan(DateTime cutoff) {
    return _backupMutex.guard(() async {
      final config = await _loadConfig();
      if (!config.enabled || !config.isConfigured) return;
      final client = _client(config);
      if (client == null) return;
      final directory = KanbanPaths.remoteBackupsDir(_remoteBase(config));
      List<File> entries;
      try {
        entries = await client.readDir(directory);
      } catch (error) {
        if (_isRemoteNotFound(error)) return;
        rethrow;
      }
      for (final file in entries) {
        if (file.isDir != true) continue;
        final name = file.name ?? file.path?.split('/').last ?? '';
        final id = name;
        if (!_isSafeBackupId(id)) continue;
        final timestamp = int.tryParse(id.split('-').first);
        if (timestamp == null) continue;
        final createdAt = DateTime.fromMillisecondsSinceEpoch(
          timestamp,
          isUtc: true,
        );
        if (!createdAt.isBefore(cutoff.toUtc())) continue;
        await client.remove(
          KanbanPaths.remoteBackupDir(_remoteBase(config), id),
        );
      }
    });
  }

  bool _isSafeBackupId(String id) =>
      id.isNotEmpty &&
      !id.contains('/') &&
      !id.contains('\\') &&
      !id.contains('..');

  Future<bool> testConnection(WebDavConfig config) async {
    final client = _client(config);
    if (client == null) return false;
    try {
      await client.ping();
      return true;
    } catch (_) {
      return false;
    }
  }

  void startPolling() {
    stopPolling();
    _pollingEnabled = true;
    _armNextPoll();
  }

  void _armNextPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_pollingEnabled) return;
    unawaited(_scheduleNextPoll());
  }

  Future<void> _scheduleNextPoll() async {
    if (!_pollingEnabled) return;
    final config = await _loadConfig();
    if (!_pollingEnabled || !config.enabled || !config.autoPull) return;

    final interval = Duration(seconds: _pollIntervalSeconds(config));
    var delay = interval;
    final cooldown = _remainingCooldown();
    if (cooldown != null && cooldown > delay) {
      delay = cooldown;
    }

    if (!_pollingEnabled) return;
    _pollTimer = Timer(delay, () async {
      try {
        if (!_pollingEnabled) return;
        final latest = await _loadConfig();
        if (!_pollingEnabled || !latest.enabled || !latest.autoPull) return;
        if (_canStartAutoSync(latest)) {
          await pullAndMerge();
        }
      } finally {
        if (_pollingEnabled) {
          _armNextPoll();
        }
      }
    });
  }

  void stopPolling() {
    _pollingEnabled = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void dispose() {
    _debounceTimer?.cancel();
    _cooldownRetryTimer?.cancel();
    _pendingCountTimer?.cancel();
    stopPolling();
    _statusController.close();
    _progressController.close();
    _pendingCountController.close();
  }
}
