import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../features/sync_conflict/workspace_snapshot.dart';
import '../features/trash/trash_models.dart';
import '../storage/kanban_paths.dart';

/// 远端 JSON 内容指纹索引（应用层维护，不依赖 WebDAV ETag）
class SyncIndex {
  static const schemaVersionValue = 1;
  static const fileName = 'sync_index.json';

  const SyncIndex({
    required this.schemaVersion,
    required this.updatedAt,
    required this.files,
  });

  final int schemaVersion;
  final int updatedAt;

  /// 相对远端根目录的路径 → 规范化 JSON 的 sha256 十六进制
  final Map<String, String> files;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'updatedAt': updatedAt,
        'files': files,
      };

  factory SyncIndex.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    final files = <String, String>{};
    if (rawFiles is Map) {
      for (final entry in rawFiles.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is String && value.isNotEmpty) {
          files[key] = value;
        }
      }
    }
    return SyncIndex(
      schemaVersion: json['schemaVersion'] as int? ?? schemaVersionValue,
      updatedAt: json['updatedAt'] as int? ?? 0,
      files: files,
    );
  }

  bool get isSupportedSchema => schemaVersion == schemaVersionValue;
}

/// 与 [_writeJson] 相同的缩进编码，保证推送字节与指纹一致
String syncCanonicalJson(Object data) =>
    const JsonEncoder.withIndent('  ').convert(data);

String syncContentHash(Object data) =>
    sha256.convert(utf8.encode(syncCanonicalJson(data))).toString();

/// 索引内使用的相对路径（不含远端根前缀）
class SyncIndexPaths {
  SyncIndexPaths._();

  static String projects = KanbanPaths.projectsFileName;
  static String appTrash = KanbanPaths.appTrashFileName;
  static String sharedContent = KanbanPaths.sharedContentFileName;

  static String projectBoard(String projectId) =>
      '${KanbanPaths.projectsDirName}/$projectId/${KanbanPaths.boardFileName}';

  static String projectSettings(String projectId) =>
      '${KanbanPaths.projectsDirName}/$projectId/${KanbanPaths.settingsFileName}';

  static String projectTrash(String projectId) =>
      '${KanbanPaths.projectsDirName}/$projectId/${KanbanPaths.trashFileName}';

  static String projectColumn(String projectId, String columnId) =>
      '${KanbanPaths.projectsDirName}/$projectId/${KanbanPaths.columnsDirName}/$columnId.json';
}

/// 由工作区快照生成完整文件指纹表（与上传落盘内容一致）
Map<String, String> buildSyncIndexFiles(ProjectWorkspaceSnapshot workspace) {
  final files = <String, String>{
    SyncIndexPaths.projects: syncContentHash(workspace.manifest.toJson()),
    SyncIndexPaths.appTrash: syncContentHash(workspace.appTrash.toJson()),
  };

  if (!workspace.sharedContent.isUninitialized) {
    files[SyncIndexPaths.sharedContent] =
        syncContentHash(workspace.sharedContent.toJson());
  }

  for (final entry in workspace.manifest.projects) {
    final projectId = entry.id;
    final board = workspace.boards[projectId];
    final settings = workspace.settings[projectId];
    if (board == null || settings == null) continue;

    final trash = workspace.projectTrash[projectId] ?? TrashBin.empty;
    files[SyncIndexPaths.projectBoard(projectId)] =
        syncContentHash(board.toMetadataJson());
    files[SyncIndexPaths.projectSettings(projectId)] =
        syncContentHash(settings.toJson());
    files[SyncIndexPaths.projectTrash(projectId)] =
        syncContentHash(trash.toJson());

    for (final column in board.columns) {
      files[SyncIndexPaths.projectColumn(projectId, column.id)] =
          syncContentHash(column.toJson());
    }
  }

  return files;
}

SyncIndex buildSyncIndex(
  ProjectWorkspaceSnapshot workspace, {
  int? updatedAt,
}) {
  return SyncIndex(
    schemaVersion: SyncIndex.schemaVersionValue,
    updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    files: buildSyncIndexFiles(workspace),
  );
}

/// 远端索引与本地 SyncBase 指纹完全一致时，可跳过全部 JSON 下载
bool syncIndexMatchesWorkspace(
  SyncIndex index,
  ProjectWorkspaceSnapshot workspace,
) {
  if (!index.isSupportedSchema) return false;
  final expected = buildSyncIndexFiles(workspace);
  if (expected.length != index.files.length) return false;
  for (final entry in expected.entries) {
    if (index.files[entry.key] != entry.value) return false;
  }
  return true;
}

/// 某相对路径是否可直接复用 SyncBase 中的 JSON 对象
bool canReuseSyncBaseJson({
  required SyncIndex? remoteIndex,
  required String relativePath,
  required Object? baseJson,
}) {
  if (remoteIndex == null || !remoteIndex.isSupportedSchema) return false;
  if (baseJson == null) return false;
  final remoteHash = remoteIndex.files[relativePath];
  if (remoteHash == null) return false;
  return remoteHash == syncContentHash(baseJson);
}
