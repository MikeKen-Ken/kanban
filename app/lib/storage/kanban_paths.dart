/// 看板路径约定（远端 WebDAV + 本地文件名常量）
class KanbanPaths {
  KanbanPaths._();

  static const storageVersion = 3;
  static const boardFileName = 'board.json';
  static const columnsDirName = 'columns';
  static const attachmentsDirName = 'attachments';
  static const attachmentFileExt = 'jpg';
  static const projectsFileName = 'projects.json';
  static const projectsDirName = 'projects';
  static const settingsFileName = 'settings.json';
  static const trashFileName = 'trash.json';
  static const appTrashFileName = 'app_trash.json';

  /// 远端根目录；兼容旧配置 `/KanbanApp/board.json`
  static String remoteBaseDir(String remotePath) {
    var path = remotePath.trim();
    if (path.isEmpty) path = '/KanbanApp';
    if (!path.startsWith('/')) path = '/$path';
    if (path.endsWith('/$boardFileName')) {
      return path.substring(0, path.length - boardFileName.length - 1);
    }
    if (path.endsWith('.json')) {
      final slash = path.lastIndexOf('/');
      return slash > 0 ? path.substring(0, slash) : '/';
    }
    if (path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  static String remoteBoardPath(String baseDir) => '$baseDir/$boardFileName';

  static String remoteColumnsDir(String baseDir) => '$baseDir/$columnsDirName';

  static String remoteColumnPath(String baseDir, String columnId) =>
      '${remoteColumnsDir(baseDir)}/$columnId.json';

  static String remoteProjectsPath(String baseDir) =>
      '$baseDir/$projectsFileName';

  static String remoteProjectsDir(String baseDir) =>
      '$baseDir/$projectsDirName';

  static String remoteProjectDir(String baseDir, String projectId) =>
      '${remoteProjectsDir(baseDir)}/$projectId';

  static String remoteProjectBoardPath(String baseDir, String projectId) =>
      '${remoteProjectDir(baseDir, projectId)}/$boardFileName';

  static String remoteProjectSettingsPath(String baseDir, String projectId) =>
      '${remoteProjectDir(baseDir, projectId)}/$settingsFileName';

  static String remoteProjectColumnsDir(String baseDir, String projectId) =>
      '${remoteProjectDir(baseDir, projectId)}/$columnsDirName';

  static String remoteProjectColumnPath(
    String baseDir,
    String projectId,
    String columnId,
  ) =>
      '${remoteProjectColumnsDir(baseDir, projectId)}/$columnId.json';

  static String remoteProjectTrashPath(String baseDir, String projectId) =>
      '${remoteProjectDir(baseDir, projectId)}/$trashFileName';

  static String remoteProjectAttachmentsDir(String baseDir, String projectId) =>
      '${remoteProjectDir(baseDir, projectId)}/$attachmentsDirName';

  static String remoteProjectAttachmentFileName(
    String attachmentId, {
    bool thumb = false,
  }) {
    final stem = thumb ? '${attachmentId}_thumb' : attachmentId;
    return '$stem.$attachmentFileExt';
  }

  static String remoteProjectAttachmentPath(
    String baseDir,
    String projectId,
    String attachmentId, {
    bool thumb = false,
  }) {
    return '${remoteProjectAttachmentsDir(baseDir, projectId)}/'
        '${remoteProjectAttachmentFileName(attachmentId, thumb: thumb)}';
  }

  static String? attachmentIdFromRemoteFileName(String fileName) {
    if (!fileName.endsWith('.$attachmentFileExt')) return null;
    final base = fileName.substring(0, fileName.length - attachmentFileExt.length - 1);
    if (base.endsWith('_thumb')) {
      return base.substring(0, base.length - 6);
    }
    return base;
  }

  static String? attachmentIdFromRemoteFile(String filePath) {
    final name = filePath.split('/').last;
    return attachmentIdFromRemoteFileName(name);
  }

  static String remoteAppTrashPath(String baseDir) =>
      '$baseDir/$appTrashFileName';

  static String? columnIdFromRemoteFile(String filePath) {
    final name = filePath.split('/').last;
    if (!name.endsWith('.json')) return null;
    return name.substring(0, name.length - 5);
  }
}
