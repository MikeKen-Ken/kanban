import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../features/trash/trash_models.dart';
import '../models/kanban_models.dart';
import '../settings/app_settings.dart';
import '../storage/board_storage.dart';
import '../features/attachments/attachment_storage.dart';
import '../features/attachments/attachment_store.dart';

/// WebDAV 连接配置（密码仅存本地 SharedPreferences）
class WebDavConfig {
  const WebDavConfig({
    required this.enabled,
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.remotePath,
    required this.autoSync,
    required this.pollIntervalSeconds,
  });

  final bool enabled;
  final String serverUrl;
  final String username;
  final String password;
  final String remotePath;
  final bool autoSync;
  final int pollIntervalSeconds;

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  WebDavConfig copyWith({
    bool? enabled,
    String? serverUrl,
    String? username,
    String? password,
    String? remotePath,
    bool? autoSync,
    int? pollIntervalSeconds,
  }) {
    return WebDavConfig(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remotePath: remotePath ?? this.remotePath,
      autoSync: autoSync ?? this.autoSync,
      pollIntervalSeconds: pollIntervalSeconds ?? this.pollIntervalSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'remotePath': remotePath,
        'autoSync': autoSync,
        'pollIntervalSeconds': pollIntervalSeconds,
      };

  factory WebDavConfig.fromJson(Map<String, dynamic> json) {
    return WebDavConfig(
      enabled: json['enabled'] as bool? ?? false,
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '/KanbanApp',
      autoSync: json['autoSync'] as bool? ?? true,
      pollIntervalSeconds: json['pollIntervalSeconds'] as int? ?? 30,
    );
  }

  static const empty = WebDavConfig(
    enabled: false,
    serverUrl: '',
    username: '',
    password: '',
    remotePath: '/KanbanApp',
    autoSync: true,
    pollIntervalSeconds: 30,
  );
}

class BoardRepository {
  BoardRepository(this._prefs, [BoardStorage? storage])
      : _storage = storage ?? BoardStorage(prefs: _prefs);

  final SharedPreferences _prefs;
  final BoardStorage _storage;
  static const _legacyBoardKey = 'kanban_board';
  static const _boardIdKey = 'kanban_board_id';
  static const _activeProjectKey = 'kanban_active_project_id';
  static const _webdavKey = 'webdav_config';
  static const _labelTrashKey = 'kanban_label_trash';

  BoardStorage get storage => _storage;

  AttachmentStore? get attachmentStore => createAttachmentStore();

  Future<void> ensureInitialized() async {
    await _storage.migrateFromLegacyIfNeeded();

    final legacy = _prefs.getString(_legacyBoardKey);
    if (legacy != null) {
      final board = KanbanBoard.fromJsonString(legacy);
      final projectId = board.id;
      await _storage.saveBoard(projectId, board);
      await _storage.saveProjectSettings(projectId, const ProjectSettings());
      final now = DateTime.now().millisecondsSinceEpoch;
      await _storage.saveManifest(ProjectsManifest(
        projects: [
          ProjectEntry(
            id: projectId,
            title: board.title,
            updatedAt: now,
            revision: 1,
          ),
        ],
        updatedAt: now,
        revision: 1,
      ));
      await _prefs.remove(_legacyBoardKey);
      await _prefs.setString(_activeProjectKey, projectId);
      return;
    }

    if (!await _storage.hasManifest()) {
      final id = _prefs.getString(_boardIdKey) ?? const Uuid().v4();
      await _prefs.setString(_boardIdKey, id);
      await _createDefaultProject(id: id);
    }
  }

  Future<String> _createDefaultProject({String? id, String? title}) async {
    final projectId = id ?? const Uuid().v4();
    final projectTitle = title ?? '我的看板';
    final board = KanbanBoard.empty(id: projectId, title: projectTitle);
    await _storage.saveBoard(projectId, board);
    await _storage.saveProjectSettings(projectId, const ProjectSettings());

    final now = DateTime.now().millisecondsSinceEpoch;
    await _storage.saveManifest(ProjectsManifest(
      projects: [
        ProjectEntry(
          id: projectId,
          title: projectTitle,
          updatedAt: now,
          revision: 1,
        ),
      ],
      updatedAt: now,
      revision: 1,
    ));
    await _prefs.setString(_activeProjectKey, projectId);
    return projectId;
  }

  Future<ProjectsManifest> loadManifest() => _storage.loadManifest();

  Future<void> saveManifest(ProjectsManifest manifest) =>
      _storage.saveManifest(manifest);

  String? loadActiveProjectId() => _prefs.getString(_activeProjectKey);

  Future<void> saveActiveProjectId(String projectId) async {
    await _prefs.setString(_activeProjectKey, projectId);
  }

  Future<KanbanBoard> loadBoard(String projectId) =>
      _storage.loadBoard(projectId);

  Future<void> saveBoard(String projectId, KanbanBoard board) =>
      _storage.saveBoard(projectId, board);

  Future<ProjectSettings> loadProjectSettings(String projectId) =>
      _storage.loadProjectSettings(projectId);

  Future<void> saveProjectSettings(
    String projectId,
    ProjectSettings settings,
  ) =>
      _storage.saveProjectSettings(projectId, settings);

  Future<TrashBin> loadProjectTrash(String projectId) =>
      _storage.loadProjectTrash(projectId);

  Future<void> saveProjectTrash(String projectId, TrashBin trash) =>
      _storage.saveProjectTrash(projectId, trash);

  Future<TrashBin> loadAppTrash() => _storage.loadAppTrash();

  Future<void> saveAppTrash(TrashBin trash) => _storage.saveAppTrash(trash);

  List<TrashItem> loadLabelTrash() {
    final raw = _prefs.getString(_labelTrashKey);
    if (raw == null) return const [];
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return (json['items'] as List<dynamic>? ?? [])
        .map((e) => TrashItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveLabelTrash(List<TrashItem> items) async {
    await _prefs.setString(
      _labelTrashKey,
      jsonEncode({
        'items': items.map((item) => item.toJson()).toList(),
      }),
    );
  }

  Future<String> createProject(String title) async {
    final projectId = const Uuid().v4();
    const settings = ProjectSettings();
    final board = KanbanBoard.empty(
      id: projectId,
      title: title,
      doneColumnTitle: settings.doneColumnName,
    );
    await _storage.saveBoard(projectId, board);
    await _storage.saveProjectSettings(projectId, const ProjectSettings());

    final manifest = await _storage.loadManifest();
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = ProjectEntry(
      id: projectId,
      title: title,
      updatedAt: now,
      revision: 1,
    );
    await _storage.saveManifest(manifest.bump().copyWith(
          projects: [...manifest.projects, entry],
        ));
    return projectId;
  }

  Future<void> deleteProject(String projectId) async {
    final manifest = await _storage.loadManifest();
    final remaining =
        manifest.projects.where((p) => p.id != projectId).toList();
    if (remaining.isEmpty) return;
    await _storage.saveManifest(manifest.bump().copyWith(projects: remaining));
    // note: 项目文件保留在磁盘，同步时会清理远端；本地暂不删除以防误操作
  }

  Future<WebDavConfig> loadWebDavConfig() async {
    final raw = _prefs.getString(_webdavKey);
    if (raw == null) return WebDavConfig.empty;
    return WebDavConfig.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> saveWebDavConfig(WebDavConfig config) async {
    await _prefs.setString(_webdavKey, jsonEncode(config.toJson()));
  }

  AppSettings loadAppSettings() => _prefs.loadAppSettings();

  Future<void> saveAppSettings(AppSettings settings) async {
    await _prefs.saveAppSettings(settings);
  }
}
