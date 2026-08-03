import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../features/shared_content/shared_content.dart';
import '../features/trash/trash_models.dart';
import '../models/kanban_models.dart';
import 'board_storage.dart';
import 'json_file_io.dart';
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
    final json = await readJsonFile(file);
    if (json == null) {
      throw StateError('projects.json 不存在或已损坏');
    }
    return ProjectsManifest.fromJson(json);
  }

  @override
  Future<void> saveManifest(ProjectsManifest manifest) async {
    final dir = await _dataDir();
    await writeJsonFileAtomic(
      KanbanPathsIo.manifestFile(dir),
      manifest.toJson(),
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
    final meta = await readJsonFile(file);
    if (meta == null) {
      throw StateError('项目 $projectId 的 board.json 不存在或已损坏');
    }

    if (KanbanBoard.isLegacyMonolithic(meta)) {
      return KanbanBoard.fromJson(meta);
    }

    final refs =
        (meta['columns'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final columns = <KanbanColumn>[];
    for (final ref in refs) {
      final id = ref['id'] as String;
      final colFile = KanbanPathsIo.projectColumnFile(dir, projectId, id);
      final colJson = await readJsonFile(colFile);
      if (colJson == null) {
        // note: 列文件损坏时用空列占位，避免整板无法加载/同步
        columns.add(
          KanbanColumn(
            id: id,
            title: id,
            order: ref['order'] as int? ?? columns.length,
            cards: const [],
          ),
        );
        continue;
      }
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
      await writeJsonFileAtomic(
        KanbanPathsIo.projectColumnFile(dir, projectId, column.id),
        column.toJson(),
      );
    }

    await writeJsonFileAtomic(
      KanbanPathsIo.projectBoardFile(dir, projectId),
      board.toMetadataJson(),
    );
  }

  @override
  Future<ProjectSettings> loadProjectSettings(String projectId) async {
    final dir = await _dataDir();
    final file = KanbanPathsIo.projectSettingsFile(dir, projectId);
    final json = await readJsonFile(file);
    if (json == null) return const ProjectSettings();
    return ProjectSettings.fromJson(json);
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
    await writeJsonFileAtomic(
      KanbanPathsIo.projectSettingsFile(dir, projectId),
      settings.toJson(),
    );
  }

  @override
  Future<TrashBin> loadProjectTrash(String projectId) async {
    final dir = await _dataDir();
    final file = KanbanPathsIo.projectTrashFile(dir, projectId);
    final json = await readJsonFile(file);
    if (json == null) return TrashBin.empty;
    return TrashBin.fromJson(json);
  }

  @override
  Future<void> saveProjectTrash(String projectId, TrashBin trash) async {
    final dir = await _dataDir();
    final projectDir = KanbanPathsIo.projectDirectory(dir, projectId);
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }
    await writeJsonFileAtomic(
      KanbanPathsIo.projectTrashFile(dir, projectId),
      trash.toJson(),
    );
  }

  @override
  Future<TrashBin> loadAppTrash() async {
    final dir = await _dataDir();
    final file = KanbanPathsIo.appTrashFile(dir);
    final json = await readJsonFile(file);
    if (json == null) return TrashBin.empty;
    return TrashBin.fromJson(json);
  }

  @override
  Future<void> saveAppTrash(TrashBin trash) async {
    final dir = await _dataDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await writeJsonFileAtomic(KanbanPathsIo.appTrashFile(dir), trash.toJson());
  }

  @override
  Future<SharedContent> loadSharedContent() async {
    final dir = await _dataDir();
    final json = await readJsonFile(KanbanPathsIo.sharedContentFile(dir));
    if (json == null) return SharedContent.empty;
    return SharedContent.fromJson(json);
  }

  @override
  Future<void> saveSharedContent(SharedContent content) async {
    final dir = await _dataDir();
    await writeJsonFileAtomic(
      KanbanPathsIo.sharedContentFile(dir),
      content.toJson(),
    );
  }

  @override
  Future<bool> migrateFromLegacyIfNeeded() async {
    final dir = await _dataDir();
    if (await KanbanPathsIo.manifestFile(dir).exists()) return false;

    final legacyBoard = KanbanPathsIo.boardFile(dir);
    if (!await legacyBoard.exists()) return false;

    final meta = await readJsonFile(legacyBoard);
    if (meta == null) return false;
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
        final colJson = await readJsonFile(colFile);
        if (colJson == null) continue;
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
