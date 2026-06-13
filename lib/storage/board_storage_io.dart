import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../models/kanban_models.dart';
import 'board_storage.dart';
import 'kanban_paths_io.dart';

BoardStorage createBoardStorage({
  Object? baseDirectory,
  SharedPreferences? prefs,
}) {
  return BoardStorageIo(baseDirectory: baseDirectory as Directory?);
}

/// 本地文件存储：projects.json + projects/{id}/board.json + settings.json + columns/
class BoardStorageIo implements BoardStorage {
  BoardStorageIo({Directory? baseDirectory}) : _baseDirectory = baseDirectory;

  final Directory? _baseDirectory;

  Future<Directory> _dataDir() async {
    final base = _baseDirectory ?? await getApplicationDocumentsDirectory();
    final dir = KanbanPathsIo.dataDirectory(base);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<bool> hasManifest() async {
    final dir = await _dataDir();
    return KanbanPathsIo.manifestFile(dir).exists();
  }

  @override
  Future<ProjectsManifest> loadManifest() async {
    final dir = await _dataDir();
    final file = KanbanPathsIo.manifestFile(dir);
    if (!await file.exists()) {
      throw StateError('projects.json 不存在');
    }
    return ProjectsManifest.fromJsonString(await file.readAsString());
  }

  @override
  Future<void> saveManifest(ProjectsManifest manifest) async {
    final dir = await _dataDir();
    await KanbanPathsIo.manifestFile(dir).writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );
  }

  @override
  Future<bool> hasProjectBoard(String projectId) async {
    final dir = await _dataDir();
    return KanbanPathsIo.projectBoardFile(dir, projectId).exists();
  }

  @override
  Future<KanbanBoard> loadBoard(String projectId) async {
    final dir = await _dataDir();
    final file = KanbanPathsIo.projectBoardFile(dir, projectId);
    if (!await file.exists()) {
      throw StateError('项目 $projectId 的 board.json 不存在');
    }

    final meta =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    if (KanbanBoard.isLegacyMonolithic(meta)) {
      return KanbanBoard.fromJson(meta);
    }

    final refs = (meta['columns'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final columns = <KanbanColumn>[];
    for (final ref in refs) {
      final id = ref['id'] as String;
      final colFile = KanbanPathsIo.projectColumnFile(dir, projectId, id);
      if (!await colFile.exists()) continue;
      final colJson =
          jsonDecode(await colFile.readAsString()) as Map<String, dynamic>;
      columns.add(KanbanColumn.fromJson(colJson));
    }

    return KanbanBoard.fromMetadataJson(meta, columns);
  }

  @override
  Future<void> saveBoard(String projectId, KanbanBoard board) async {
    final dir = await _dataDir();
    final projectDir = KanbanPathsIo.projectDirectory(dir, projectId);
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }

    final columnsDir = KanbanPathsIo.projectColumnsDirectory(dir, projectId);
    if (!await columnsDir.exists()) {
      await columnsDir.create(recursive: true);
    }

    final nextIds = board.columns.map((c) => c.id).toSet();
    if (await columnsDir.exists()) {
      await for (final entity in columnsDir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith('.json')) continue;
        final id = name.substring(0, name.length - 5);
        if (!nextIds.contains(id)) {
          await entity.delete();
        }
      }
    }

    for (final column in board.columns) {
      await KanbanPathsIo.projectColumnFile(dir, projectId, column.id)
          .writeAsString(
        const JsonEncoder.withIndent('  ').convert(column.toJson()),
      );
    }

    await KanbanPathsIo.projectBoardFile(dir, projectId).writeAsString(
      const JsonEncoder.withIndent('  ').convert(board.toMetadataJson()),
    );
  }

  @override
  Future<ProjectSettings> loadProjectSettings(String projectId) async {
    final dir = await _dataDir();
    final file = KanbanPathsIo.projectSettingsFile(dir, projectId);
    if (!await file.exists()) {
      return const ProjectSettings();
    }
    return ProjectSettings.fromJsonString(await file.readAsString());
  }

  @override
  Future<void> saveProjectSettings(
    String projectId,
    ProjectSettings settings,
  ) async {
    final dir = await _dataDir();
    final projectDir = KanbanPathsIo.projectDirectory(dir, projectId);
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }
    await KanbanPathsIo.projectSettingsFile(dir, projectId).writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }

  @override
  Future<bool> migrateFromLegacyIfNeeded() async {
    final dir = await _dataDir();
    if (await KanbanPathsIo.manifestFile(dir).exists()) return false;

    final legacyBoard = KanbanPathsIo.boardFile(dir);
    if (!await legacyBoard.exists()) return false;

    final meta =
        jsonDecode(await legacyBoard.readAsString()) as Map<String, dynamic>;
    KanbanBoard board;

    if (KanbanBoard.isLegacyMonolithic(meta)) {
      board = KanbanBoard.fromJson(meta);
    } else {
      final refs = (meta['columns'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final columns = <KanbanColumn>[];
      for (final ref in refs) {
        final id = ref['id'] as String;
        final colFile = KanbanPathsIo.columnFile(dir, id);
        if (!await colFile.exists()) continue;
        final colJson =
            jsonDecode(await colFile.readAsString()) as Map<String, dynamic>;
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

    // note: 清理旧版 v2 文件
    final legacyColumns = KanbanPathsIo.columnsDirectory(dir);
    if (await legacyColumns.exists()) {
      await legacyColumns.delete(recursive: true);
    }
    if (await legacyBoard.exists()) {
      await legacyBoard.delete();
    }

    return true;
  }

  /// note: 供 BoardRepository 在无数据时创建默认项目
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
