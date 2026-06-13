import 'dart:io';

import 'package:path/path.dart' as p;

import 'kanban_paths.dart';

/// 本地文件路径（仅 dart:io 平台）
class KanbanPathsIo {
  KanbanPathsIo._();

  static Directory dataDirectory(Directory base) =>
      Directory(p.join(base.path, 'kanban'));

  static File boardFile(Directory dataDir) =>
      File(p.join(dataDir.path, KanbanPaths.boardFileName));

  static Directory columnsDirectory(Directory dataDir) =>
      Directory(p.join(dataDir.path, KanbanPaths.columnsDirName));

  static File columnFile(Directory dataDir, String columnId) =>
      File(p.join(columnsDirectory(dataDir).path, '$columnId.json'));

  static File manifestFile(Directory dataDir) =>
      File(p.join(dataDir.path, KanbanPaths.projectsFileName));

  static Directory projectsDirectory(Directory dataDir) =>
      Directory(p.join(dataDir.path, KanbanPaths.projectsDirName));

  static Directory projectDirectory(Directory dataDir, String projectId) =>
      Directory(p.join(projectsDirectory(dataDir).path, projectId));

  static File projectBoardFile(Directory dataDir, String projectId) =>
      File(p.join(projectDirectory(dataDir, projectId).path,
          KanbanPaths.boardFileName));

  static File projectSettingsFile(Directory dataDir, String projectId) =>
      File(p.join(projectDirectory(dataDir, projectId).path,
          KanbanPaths.settingsFileName));

  static Directory projectColumnsDirectory(
    Directory dataDir,
    String projectId,
  ) =>
      Directory(p.join(
        projectDirectory(dataDir, projectId).path,
        KanbanPaths.columnsDirName,
      ));

  static File projectColumnFile(
    Directory dataDir,
    String projectId,
    String columnId,
  ) =>
      File(p.join(
        projectColumnsDirectory(dataDir, projectId).path,
        '$columnId.json',
      ));

  static File projectTrashFile(Directory dataDir, String projectId) =>
      File(p.join(
        projectDirectory(dataDir, projectId).path,
        KanbanPaths.trashFileName,
      ));

  static File appTrashFile(Directory dataDir) =>
      File(p.join(dataDir.path, KanbanPaths.appTrashFileName));
}
