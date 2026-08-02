import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:webdav_client/webdav_client.dart';

import '../features/attachments/attachment_sync_adapter.dart';
import '../features/attachments/attachment_sync_plan.dart';
import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../features/sync_conflict/sync_conflict.dart';
import '../features/trash/trash_models.dart';
import '../models/kanban_models.dart';
import '../storage/json_file_io.dart';
import '../storage/kanban_paths.dart';
import 'webdav_config.dart';

export '../features/sync_conflict/workspace_snapshot.dart';

enum SyncStatus { idle, syncing, success, error }

/// 自动 WebDAV 同步：本地变更后防抖上传，启动/轮询时拉取合并
class WebDavSyncService {
  WebDavSyncService({
    required Future<WebDavConfig> Function() loadConfig,
    required Future<ProjectWorkspaceSnapshot> Function() loadWorkspace,
    required Future<void> Function(ProjectWorkspaceSnapshot workspace)
        saveWorkspace,
    required SyncBaseStore syncBaseStore,
    AttachmentSyncAdapter? attachmentSync,
  })  : _loadConfig = loadConfig,
        _loadWorkspace = loadWorkspace,
        _saveWorkspace = saveWorkspace,
        _syncBaseStore = syncBaseStore,
        _attachmentSync = attachmentSync ?? AttachmentSyncAdapter(null);

  final Future<WebDavConfig> Function() _loadConfig;
  final Future<ProjectWorkspaceSnapshot> Function() _loadWorkspace;
  final Future<void> Function(ProjectWorkspaceSnapshot workspace)
      _saveWorkspace;
  final SyncBaseStore _syncBaseStore;
  final AttachmentSyncAdapter _attachmentSync;

  SyncStatus status = SyncStatus.idle;
  String? lastError;
  String? attachmentSyncWarning;
  DateTime? lastSyncedAt;

  /// 最近一次附件上传失败的原始错误（用于提示细节）
  String? _lastAttachmentError;

  Timer? _debounceTimer;
  Timer? _pollTimer;
  Timer? _cooldownRetryTimer;
  int _pushScheduleGen = 0;
  bool _pollingEnabled = false;
  bool _pushInFlight = false;
  bool _pushPending = false;
  bool _pushPendingForce = false;
  bool _syncInFlight = false;
  bool _pullPending = false;
  bool _pullPendingUserInitiated = false;

  /// 上次开始同步尝试的时间（成功/失败都更新，用于节流）
  DateTime? _lastAttemptAt;
  /// 限流/失败后的冷却截止时间
  DateTime? _cooldownUntil;
  int _consecutiveFailures = 0;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

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
    for (final path in _directoryPathCandidates(dir)) {
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
    await _ensureParentDir(client, path);
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );
    await client.write(path, bytes);
  }

  Future<Map<String, dynamic>?> _readJson(
    Client client,
    String path,
  ) async {
    try {
      final data = await client.read(path);
      final json = tryDecodeJsonBytes(data, path: path);
      if (json != null) return json;
      // note: 远端个别文件损坏时不拖垮整次同步；由调用方处理 null
      return null;
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
    await _ensureParentDir(client, path);
    // note: webdav_client.write() 会把字节拆成「每字节一个 chunk」的 Stream，
    // 截图 JPEG 体积稍大时极易超时；改走临时文件 + writeFromFile（按块流式上传）。
    final tmp = io.File(
      '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}'
      'kanban_webdav_${DateTime.now().microsecondsSinceEpoch}.bin',
    );
    try {
      await tmp.writeAsBytes(bytes, flush: true);
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
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _writeBytes(client, path, bytes);
    }
  }

  Future<Uint8List?> _readBytes(Client client, String path) async {
    try {
      final data = await client.read(path);
      return Uint8List.fromList(data);
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
        return await _attachmentSync.exists(projectId, attachmentId, thumb: thumb);
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
        if (await _attachmentSync.exists(projectId, attachmentId, thumb: thumb)) {
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
    bool cleanupOrphans = true,
  }) async {
    if (!_attachmentSync.isAvailable) return 0;

    var failed = 0;
    final keepIds = _attachmentSync.referencedIds(board, trash);
    final attachmentsDir =
        KanbanPaths.remoteProjectAttachmentsDir(base, projectId);
    final remoteNames = await _listRemoteAttachmentNames(client, attachmentsDir);

    for (final id in keepIds) {
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
    TrashBin trash,
  ) async {
    if (!_attachmentSync.isAvailable) return 0;

    var failed = 0;
    final keepIds = _attachmentSync.referencedIds(board, trash);
    final attachmentsDir =
        KanbanPaths.remoteProjectAttachmentsDir(base, projectId);
    for (final id in keepIds) {
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

  Future<int> _pushProject(
    Client client,
    String base,
    String projectId,
    KanbanBoard board,
    ProjectSettings settings,
    TrashBin trash,
  ) async {
    final projectBase = KanbanPaths.remoteProjectDir(base, projectId);
    try {
      await client.mkdirAll(projectBase);
    } catch (_) {
      // note: 目录已存在时忽略
    }
    // note: 先写列文件、再写 board 元数据，避免其他端拉取时元数据已列出列 id 但列文件尚未上传
    for (final column in board.columns) {
      await _writeJson(
        client,
        KanbanPaths.remoteProjectColumnPath(base, projectId, column.id),
        column.toJson(),
      );
    }
    await _cleanupRemoteColumns(
      client,
      KanbanPaths.remoteProjectColumnsDir(base, projectId),
      board.columns.map((c) => c.id).toSet(),
    );
    await _writeJson(
      client,
      KanbanPaths.remoteProjectBoardPath(base, projectId),
      board.toMetadataJson(),
    );
    await _writeJson(
      client,
      KanbanPaths.remoteProjectSettingsPath(base, projectId),
      settings.toJson(),
    );
    await _writeJson(
      client,
      KanbanPaths.remoteProjectTrashPath(base, projectId),
      trash.toJson(),
    );
    final attachmentFailures = await _pushProjectAttachments(
      client,
      base,
      projectId,
      board,
      trash,
    );
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

  Future<void> pushNow({bool force = false}) async {
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

    _pushInFlight = true;
    _noteAttempt();
    _setStatus(SyncStatus.syncing);
    _lastAttachmentError = null;

    try {
      final workspace = await _loadWorkspace();
      final base = _remoteBase(config);
      var attachmentFailures = 0;

      await _writeJson(
        client,
        KanbanPaths.remoteProjectsPath(base),
        workspace.manifest.toJson(),
      );
      await _writeJson(
        client,
        KanbanPaths.remoteAppTrashPath(base),
        workspace.appTrash.toJson(),
      );

      for (final entry in workspace.manifest.projects) {
        final board = workspace.boards[entry.id];
        final settings = workspace.settings[entry.id];
        final trash = workspace.projectTrash[entry.id] ?? TrashBin.empty;
        if (board == null || settings == null) continue;
        attachmentFailures += await _pushProject(
          client,
          base,
          entry.id,
          board,
          settings,
          trash,
        );
      }

      await _cleanupRemoteProjects(
        client,
        KanbanPaths.remoteProjectsDir(base),
        workspace.manifest.projects.map((p) => p.id).toSet(),
      );

      await _syncBaseStore.save(workspace);
      _applyAttachmentSyncWarning(attachmentFailures);
      _noteSuccess();
      _setStatus(SyncStatus.success);
    } catch (e) {
      _noteFailure(e);
      _setStatus(SyncStatus.error, error: e.toString());
    } finally {
      _pushInFlight = false;
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

    final refs = (meta['columns'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
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

  Future<ProjectWorkspaceSnapshot?> pullRemote() async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return null;

    final client = _client(config);
    if (client == null) return null;

    final base = _remoteBase(config);
    final manifestPath = KanbanPaths.remoteProjectsPath(base);

    try {
      final manifestJson = await _readJson(client, manifestPath);

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
        final boardMeta = await _readJson(
          client,
          KanbanPaths.remoteProjectBoardPath(base, projectId),
        );
        if (boardMeta == null) continue;

        if (KanbanBoard.isLegacyMonolithic(boardMeta)) {
          boards[projectId] = KanbanBoard.fromJson(boardMeta);
        } else {
          final refs = (boardMeta['columns'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          final columns = <KanbanColumn>[];
          for (final ref in refs) {
            final colId = ref['id'] as String;
            final colJson = await _readJson(
              client,
              KanbanPaths.remoteProjectColumnPath(base, projectId, colId),
            );
            if (colJson != null) {
              columns.add(KanbanColumn.fromJson(colJson));
            }
          }
          boards[projectId] = KanbanBoard.fromMetadataJson(boardMeta, columns);
        }

        final settingsJson = await _readJson(
          client,
          KanbanPaths.remoteProjectSettingsPath(base, projectId),
        );
        settings[projectId] = settingsJson == null
            ? const ProjectSettings()
            : ProjectSettings.fromJson(settingsJson);

        final trashJson = await _readJson(
          client,
          KanbanPaths.remoteProjectTrashPath(base, projectId),
        );
        projectTrash[projectId] = trashJson == null
            ? TrashBin.empty
            : TrashBin.fromJson(trashJson);
      }

      final appTrashJson = await _readJson(
        client,
        KanbanPaths.remoteAppTrashPath(base),
      );
      final appTrash = appTrashJson == null
          ? TrashBin.empty
          : TrashBin.fromJson(appTrashJson);

      return ProjectWorkspaceSnapshot(
        manifest: manifest,
        boards: boards,
        settings: settings,
        projectTrash: projectTrash,
        appTrash: appTrash,
      );
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

  Future<void> pullAndMerge({bool userInitiated = false}) async {
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

    _syncInFlight = true;
    _noteAttempt();
    _setStatus(SyncStatus.syncing);
    _lastAttachmentError = null;
    try {
      final local = await _loadWorkspace();
      final remote = await pullRemote();
      if (remote == null) {
        // note: 远端为空时上传本地；先释放锁再 push
        _syncInFlight = false;
        await pushNow(force: true);
        return;
      }

      final syncBase = await _syncBaseStore.load();
      final merged = _mergeWorkspaces(local, remote, syncBase);
      await _saveWorkspace(merged);
      await _syncBaseStore.save(merged);

      final client = _client(config);
      var attachmentFailures = 0;
      if (client != null) {
        final base = _remoteBase(config);
        for (final entry in merged.manifest.projects) {
          final board = merged.boards[entry.id];
          if (board == null) continue;
          final trash = merged.projectTrash[entry.id] ?? TrashBin.empty;
          attachmentFailures += await _pullProjectAttachments(
            client,
            base,
            entry.id,
            board,
            trash,
          );
        }
      }

      _applyAttachmentSyncWarning(attachmentFailures);

      // note: 合并结果与远端一致时跳过全量 JSON 回推，但仍需补传本地有、远端缺的附件
      if (_workspaceJsonEquals(merged, remote)) {
        if (shouldReconcileAttachmentsWhenJsonEquals(
              jsonEquals: true,
              attachmentSyncAvailable: _attachmentSync.isAvailable,
            ) &&
            client != null) {
          final base = _remoteBase(config);
          for (final entry in merged.manifest.projects) {
            final board = merged.boards[entry.id];
            if (board == null) continue;
            final trash = merged.projectTrash[entry.id] ?? TrashBin.empty;
            attachmentFailures += await _pushProjectAttachments(
              client,
              base,
              entry.id,
              board,
              trash,
              cleanupOrphans: false,
            );
          }
          _applyAttachmentSyncWarning(attachmentFailures);
        }
        _noteSuccess();
        _setStatus(SyncStatus.success);
        return;
      }

      // note: 合并后回推，避免本地并集结果只留本机
      _syncInFlight = false;
      await pushNow(force: true);
    } catch (e) {
      _noteFailure(e);
      _setStatus(SyncStatus.error, error: e.toString());
    } finally {
      _syncInFlight = false;
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
    run();
  }

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
    if (!_pollingEnabled || !config.enabled || !config.autoSync) return;

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
        if (!_pollingEnabled || !latest.enabled || !latest.autoSync) return;
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
    stopPolling();
    _statusController.close();
  }
}
