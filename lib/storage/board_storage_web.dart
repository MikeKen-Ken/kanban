import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../models/kanban_models.dart';
import 'board_storage.dart';

BoardStorage createBoardStorage({
  Object? baseDirectory,
  SharedPreferences? prefs,
}) {
  if (prefs == null) {
    throw StateError('Web 端 BoardStorage 需要 SharedPreferences');
  }
  return BoardStorageWeb(prefs);
}

/// note: Web 无文件系统，用 SharedPreferences（底层 localStorage）模拟分文件结构
class BoardStorageWeb implements BoardStorage {
  BoardStorageWeb(this._prefs);

  final SharedPreferences _prefs;

  static const _manifestKey = 'kanban_v3_manifest';
  static const _legacyMetaKey = 'kanban_v2_board_meta';
  static const _legacyColumnIndexKey = 'kanban_v2_column_ids';

  String _projectMetaKey(String projectId) => 'kanban_v3_project_${projectId}_meta';
  String _projectSettingsKey(String projectId) =>
      'kanban_v3_project_${projectId}_settings';
  String _projectColumnKey(String projectId, String columnId) =>
      'kanban_v3_project_${projectId}_column_$columnId';
  String _projectColumnIndexKey(String projectId) =>
      'kanban_v3_project_${projectId}_column_ids';

  @override
  Future<bool> hasManifest() async => _prefs.containsKey(_manifestKey);

  @override
  Future<ProjectsManifest> loadManifest() async {
    final raw = _prefs.getString(_manifestKey);
    if (raw == null) throw StateError('projects manifest 不存在');
    return ProjectsManifest.fromJsonString(raw);
  }

  @override
  Future<void> saveManifest(ProjectsManifest manifest) async {
    await _prefs.setString(
      _manifestKey,
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );
  }

  @override
  Future<bool> hasProjectBoard(String projectId) async {
    return _prefs.containsKey(_projectMetaKey(projectId));
  }

  @override
  Future<KanbanBoard> loadBoard(String projectId) async {
    final metaRaw = _prefs.getString(_projectMetaKey(projectId));
    if (metaRaw == null) {
      throw StateError('项目 $projectId board 元数据不存在');
    }

    final meta = jsonDecode(metaRaw) as Map<String, dynamic>;

    if (KanbanBoard.isLegacyMonolithic(meta)) {
      return KanbanBoard.fromJson(meta);
    }

    final refs = (meta['columns'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final columns = <KanbanColumn>[];
    for (final ref in refs) {
      final id = ref['id'] as String;
      final colRaw = _prefs.getString(_projectColumnKey(projectId, id));
      if (colRaw == null) continue;
      final colJson = jsonDecode(colRaw) as Map<String, dynamic>;
      columns.add(KanbanColumn.fromJson(colJson));
    }

    return KanbanBoard.fromMetadataJson(meta, columns);
  }

  @override
  Future<void> saveBoard(String projectId, KanbanBoard board) async {
    final nextIds = board.columns.map((c) => c.id).toList();
    final prevIds =
        _prefs.getStringList(_projectColumnIndexKey(projectId)) ?? const [];

    for (final id in prevIds) {
      if (!nextIds.contains(id)) {
        await _prefs.remove(_projectColumnKey(projectId, id));
      }
    }

    final encoder = const JsonEncoder.withIndent('  ');
    for (final column in board.columns) {
      await _prefs.setString(
        _projectColumnKey(projectId, column.id),
        encoder.convert(column.toJson()),
      );
    }

    await _prefs.setStringList(_projectColumnIndexKey(projectId), nextIds);
    await _prefs.setString(
      _projectMetaKey(projectId),
      encoder.convert(board.toMetadataJson()),
    );
  }

  @override
  Future<ProjectSettings> loadProjectSettings(String projectId) async {
    final raw = _prefs.getString(_projectSettingsKey(projectId));
    if (raw == null) return const ProjectSettings();
    return ProjectSettings.fromJsonString(raw);
  }

  @override
  Future<void> saveProjectSettings(
    String projectId,
    ProjectSettings settings,
  ) async {
    await _prefs.setString(
      _projectSettingsKey(projectId),
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }

  @override
  Future<bool> migrateFromLegacyIfNeeded() async {
    if (_prefs.containsKey(_manifestKey)) return false;
    if (!_prefs.containsKey(_legacyMetaKey)) return false;

    final metaRaw = _prefs.getString(_legacyMetaKey)!;
    final meta = jsonDecode(metaRaw) as Map<String, dynamic>;
    KanbanBoard board;

    if (KanbanBoard.isLegacyMonolithic(meta)) {
      board = KanbanBoard.fromJson(meta);
    } else {
      final refs = (meta['columns'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final columns = <KanbanColumn>[];
      for (final ref in refs) {
        final id = ref['id'] as String;
        final colRaw = _prefs.getString('kanban_v2_column_$id');
        if (colRaw == null) continue;
        final colJson = jsonDecode(colRaw) as Map<String, dynamic>;
        columns.add(KanbanColumn.fromJson(colJson));
      }
      board = KanbanBoard.fromMetadataJson(meta, columns);
    }

    final projectId = board.id;
    await saveBoard(projectId, board);
    await saveProjectSettings(projectId, const ProjectSettings());

    final now = DateTime.now().millisecondsSinceEpoch;
    await saveManifest(ProjectsManifest(
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

    // note: 清理旧版 v2 键
    final prevIds = _prefs.getStringList(_legacyColumnIndexKey) ?? const [];
    for (final id in prevIds) {
      await _prefs.remove('kanban_v2_column_$id');
    }
    await _prefs.remove(_legacyColumnIndexKey);
    await _prefs.remove(_legacyMetaKey);

    return true;
  }

  Future<String> createDefaultProject({String? id, String? title}) async {
    final projectId = id ?? const Uuid().v4();
    final projectTitle = title ?? '我的看板';
    final board = KanbanBoard.empty(id: projectId, title: projectTitle);
    await saveBoard(projectId, board);
    await saveProjectSettings(projectId, const ProjectSettings());

    final now = DateTime.now().millisecondsSinceEpoch;
    await saveManifest(ProjectsManifest(
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
    return projectId;
  }
}
