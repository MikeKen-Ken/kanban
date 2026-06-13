import 'package:shared_preferences/shared_preferences.dart';

import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../models/kanban_models.dart';
import 'board_storage_stub.dart'
    if (dart.library.io) 'board_storage_io.dart'
    if (dart.library.html) 'board_storage_web.dart';

/// 看板本地存储抽象（Web 用 SharedPreferences，桌面/移动端用文件）
abstract class BoardStorage {
  Future<bool> hasManifest();
  Future<ProjectsManifest> loadManifest();
  Future<void> saveManifest(ProjectsManifest manifest);

  Future<bool> hasProjectBoard(String projectId);
  Future<KanbanBoard> loadBoard(String projectId);
  Future<void> saveBoard(String projectId, KanbanBoard board);

  Future<ProjectSettings> loadProjectSettings(String projectId);
  Future<void> saveProjectSettings(String projectId, ProjectSettings settings);

  /// 从 v2 单项目结构迁移到 v3 多项目结构
  Future<bool> migrateFromLegacyIfNeeded();

  factory BoardStorage({
    Object? baseDirectory,
    required SharedPreferences prefs,
  }) {
    return createBoardStorage(
      baseDirectory: baseDirectory,
      prefs: prefs,
    );
  }
}
