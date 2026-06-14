import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:webdav_client/webdav_client.dart';

import '../features/attachments/attachment_sync_adapter.dart';
import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../features/trash/trash_models.dart';
import '../models/kanban_models.dart';
import '../storage/kanban_paths.dart';
import 'webdav_config.dart';

enum SyncStatus { idle, syncing, success, error }

/// 项目工作区快照，用于同步
class ProjectWorkspaceSnapshot {
  const ProjectWorkspaceSnapshot({
    required this.manifest,
    required this.boards,
    required this.settings,
    this.projectTrash = const {},
    this.appTrash = TrashBin.empty,
  });

  final ProjectsManifest manifest;
  final Map<String, KanbanBoard> boards;
  final Map<String, ProjectSettings> settings;
  final Map<String, TrashBin> projectTrash;
  final TrashBin appTrash;
}

/// 自动 WebDAV 同步：本地变更后防抖上传，启动/轮询时拉取合并
class WebDavSyncService {
  WebDavSyncService({
    required Future<WebDavConfig> Function() loadConfig,
    required Future<ProjectWorkspaceSnapshot> Function() loadWorkspace,
    required Future<void> Function(ProjectWorkspaceSnapshot workspace)
        saveWorkspace,
    AttachmentSyncAdapter? attachmentSync,
  })  : _loadConfig = loadConfig,
        _loadWorkspace = loadWorkspace,
        _saveWorkspace = saveWorkspace,
        _attachmentSync = attachmentSync ?? AttachmentSyncAdapter(null);

  final Future<WebDavConfig> Function() _loadConfig;
  final Future<ProjectWorkspaceSnapshot> Function() _loadWorkspace;
  final Future<void> Function(ProjectWorkspaceSnapshot workspace)
      _saveWorkspace;
  final AttachmentSyncAdapter _attachmentSync;

  static const debounceDuration = Duration(milliseconds: 1500);

  SyncStatus status = SyncStatus.idle;
  String? lastError;
  String? attachmentSyncWarning;
  DateTime? lastSyncedAt;

  Timer? _debounceTimer;
  Timer? _pollTimer;
  bool _pushInFlight = false;
  bool _pushPending = false;

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
      if (path.startsWith('/')) return path;
      final prefix = parentDir.endsWith('/') ? parentDir : '$parentDir/';
      return '$prefix$path';
    }
    final name = file.name?.trim();
    if (name != null && name.isNotEmpty) {
      final prefix = parentDir.endsWith('/') ? parentDir : '$parentDir/';
      return '$prefix$name';
    }
    return parentDir;
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

  void schedulePush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
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
      return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    } on Object catch (e) {
      if (_isRemoteNotFound(e)) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> _writeBytes(Client client, String path, Uint8List bytes) async {
    await _ensureParentDir(client, path);
    await client.write(path, bytes);
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
        bytes = await _readBytes(client, _remoteFilePath(attachmentsDir, file));
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
    TrashBin trash,
  ) async {
    if (!_attachmentSync.isAvailable) return 0;

    var failed = 0;
    final keepIds = _attachmentSync.referencedIds(board, trash);
    for (final id in keepIds) {
      for (final thumb in const [false, true]) {
        if (!await _attachmentSync.exists(projectId, id, thumb: thumb)) {
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
          await _writeBytes(
            client,
            KanbanPaths.remoteProjectAttachmentPath(
              base,
              projectId,
              id,
              thumb: thumb,
            ),
            bytes,
          );
        } catch (_) {
          if (!thumb) failed++;
        }
      }
    }

    try {
      await _cleanupRemoteAttachments(
        client,
        KanbanPaths.remoteProjectAttachmentsDir(base, projectId),
        keepIds,
      );
    } catch (_) {
      // note: 远端孤儿清理失败不影响已上传附件
    }
    try {
      await _attachmentSync.deleteOrphans(projectId, keepIds);
    } catch (_) {
      // note: 本地孤儿清理失败不影响同步结果
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
      attachmentSyncWarning = '$failedCount 个图片附件同步失败，可点击同步图标重试';
    } else {
      attachmentSyncWarning = null;
    }
  }

  Future<void> pushNow() async {
    if (_pushInFlight) {
      _pushPending = true;
      return;
    }
    final config = await _loadConfig();
    if (!config.enabled || !config.autoSync || !config.isConfigured) return;

    final client = _client(config);
    if (client == null) return;

    _pushInFlight = true;
    _setStatus(SyncStatus.syncing);

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

      _applyAttachmentSyncWarning(attachmentFailures);
      _setStatus(SyncStatus.success);
    } catch (e) {
      _setStatus(SyncStatus.error, error: e.toString());
    } finally {
      _pushInFlight = false;
      if (_pushPending) {
        _pushPending = false;
        unawaited(pushNow());
      }
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
  ) {
    final mergedManifest = local.manifest.mergeWith(remote.manifest);

    final allIds = <String>{
      ...local.boards.keys,
      ...remote.boards.keys,
      ...mergedManifest.projects.map((p) => p.id),
    };

    final mergedBoards = <String, KanbanBoard>{};
    final mergedSettings = <String, ProjectSettings>{};
    final mergedProjectTrash = <String, TrashBin>{};

    for (final id in allIds) {
      final localBoard = local.boards[id];
      final remoteBoard = remote.boards[id];
      if (localBoard != null && remoteBoard != null) {
        mergedBoards[id] = localBoard.mergeWith(remoteBoard);
      } else {
        mergedBoards[id] = localBoard ?? remoteBoard!;
      }

      final localSettings = local.settings[id] ?? const ProjectSettings();
      final remoteSettings = remote.settings[id] ?? const ProjectSettings();
      mergedSettings[id] = localSettings.mergeWith(remoteSettings);

      final localTrash = local.projectTrash[id] ?? TrashBin.empty;
      final remoteTrash = remote.projectTrash[id] ?? TrashBin.empty;
      mergedProjectTrash[id] = localTrash.mergeWith(remoteTrash);
    }

    return ProjectWorkspaceSnapshot(
      manifest: mergedManifest,
      boards: mergedBoards,
      settings: mergedSettings,
      projectTrash: mergedProjectTrash,
      appTrash: local.appTrash.mergeWith(remote.appTrash),
    );
  }

  bool _localIsNewer(
    ProjectWorkspaceSnapshot local,
    ProjectWorkspaceSnapshot remote,
  ) {
    if (local.manifest.revision > remote.manifest.revision) return true;
    if (local.manifest.revision < remote.manifest.revision) return false;
    return local.manifest.updatedAt > remote.manifest.updatedAt;
  }

  Future<void> pullAndMerge() async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;

    _setStatus(SyncStatus.syncing);
    try {
      final local = await _loadWorkspace();
      final remote = await pullRemote();
      if (remote == null) {
        await pushNow();
        return;
      }
      final merged = _mergeWorkspaces(local, remote);
      await _saveWorkspace(merged);

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

      if (_localIsNewer(local, remote)) {
        await pushNow();
      } else {
        _setStatus(SyncStatus.success);
      }
    } catch (e) {
      _setStatus(SyncStatus.error, error: e.toString());
    }
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
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final config = await _loadConfig();
      if (!config.enabled || !config.autoSync) return;
      final interval = config.pollIntervalSeconds;
      final last = lastSyncedAt;
      if (last != null &&
          DateTime.now().difference(last).inSeconds < interval) {
        return;
      }
      await pullAndMerge();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void dispose() {
    _debounceTimer?.cancel();
    stopPolling();
    _statusController.close();
  }
}
