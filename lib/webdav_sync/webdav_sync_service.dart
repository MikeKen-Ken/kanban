import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:webdav_client/webdav_client.dart';

import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
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
  });

  final ProjectsManifest manifest;
  final Map<String, KanbanBoard> boards;
  final Map<String, ProjectSettings> settings;
}

/// 自动 WebDAV 同步：本地变更后防抖上传，启动/轮询时拉取合并
class WebDavSyncService {
  WebDavSyncService({
    required Future<WebDavConfig> Function() loadConfig,
    required Future<ProjectWorkspaceSnapshot> Function() loadWorkspace,
    required Future<void> Function(ProjectWorkspaceSnapshot workspace)
        saveWorkspace,
  })  : _loadConfig = loadConfig,
        _loadWorkspace = loadWorkspace,
        _saveWorkspace = saveWorkspace;

  final Future<WebDavConfig> Function() _loadConfig;
  final Future<ProjectWorkspaceSnapshot> Function() _loadWorkspace;
  final Future<void> Function(ProjectWorkspaceSnapshot workspace)
      _saveWorkspace;

  static const debounceDuration = Duration(milliseconds: 1500);

  SyncStatus status = SyncStatus.idle;
  String? lastError;
  DateTime? lastSyncedAt;

  Timer? _debounceTimer;
  Timer? _pollTimer;
  bool _pushInFlight = false;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  Client? _client(WebDavConfig config) {
    if (!config.isConfigured) return null;
    var url = config.serverUrl.trim();
    if (!url.endsWith('/')) url = '$url/';
    return newClient(
      url,
      user: config.username.trim(),
      password: config.password,
      debug: false,
    );
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
      final message = e.toString().toLowerCase();
      if (message.contains('404') || message.contains('not found')) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> _pushProject(
    Client client,
    String base,
    String projectId,
    KanbanBoard board,
    ProjectSettings settings,
  ) async {
    final projectBase = KanbanPaths.remoteProjectDir(base, projectId);
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
    // note: 确保项目目录存在（某些 WebDAV 需要）
    try {
      await client.mkdirAll(projectBase);
    } catch (_) {}
  }

  Future<void> pushNow() async {
    if (_pushInFlight) return;
    final config = await _loadConfig();
    if (!config.enabled || !config.autoSync || !config.isConfigured) return;

    final client = _client(config);
    if (client == null) return;

    _pushInFlight = true;
    _setStatus(SyncStatus.syncing);

    try {
      final workspace = await _loadWorkspace();
      final base = _remoteBase(config);

      await _writeJson(
        client,
        KanbanPaths.remoteProjectsPath(base),
        workspace.manifest.toJson(),
      );

      for (final entry in workspace.manifest.projects) {
        final board = workspace.boards[entry.id];
        final settings = workspace.settings[entry.id];
        if (board == null || settings == null) continue;
        await _pushProject(client, base, entry.id, board, settings);
      }

      await _cleanupRemoteProjects(
        client,
        KanbanPaths.remoteProjectsDir(base),
        workspace.manifest.projects.map((p) => p.id).toSet(),
      );

      _setStatus(SyncStatus.success);
    } catch (e) {
      _setStatus(SyncStatus.error, error: e.toString());
    } finally {
      _pushInFlight = false;
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
      }

      return ProjectWorkspaceSnapshot(
        manifest: manifest,
        boards: boards,
        settings: settings,
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
    }

    return ProjectWorkspaceSnapshot(
      manifest: mergedManifest,
      boards: mergedBoards,
      settings: mergedSettings,
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
