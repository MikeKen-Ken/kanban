import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/kanban_models.dart';
import '../../storage/kanban_paths_io.dart';
import 'attachment_image_processor.dart';
import 'attachment_store.dart';
import '../wallpapers/wallpaper_models.dart';
import 'card_file_mime.dart';

AttachmentStore? createAttachmentStore({Object? baseDirectory}) {
  return AttachmentStorage(baseDirectory: baseDirectory as Directory?);
}

/// 卡片附件本地文件读写（Android / Windows）
class AttachmentStorage implements AttachmentStore {
  AttachmentStorage({Directory? baseDirectory})
      : _baseDirectory = baseDirectory;

  final Directory? _baseDirectory;

  Future<Directory> _dataDir() async {
    final base = _baseDirectory ?? await getApplicationDocumentsDirectory();
    final dir = KanbanPathsIo.dataDirectory(base);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _attachmentsDir(String projectId) async {
    final dir = await _dataDir();
    final attachmentsDir =
        KanbanPathsIo.projectAttachmentsDirectory(dir, projectId);
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }
    return attachmentsDir;
  }

  @override
  Future<CardAttachment> saveImage({
    required String projectId,
    required Uint8List sourceBytes,
    required String fileName,
    required int order,
    int? createdAt,
  }) async {
    final processed = processAttachmentImage(sourceBytes);
    if (processed == null) {
      throw StateError('无法解析图片');
    }

    final id = const Uuid().v4();
    final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    await _attachmentsDir(projectId);

    final fullFile = await _attachmentFile(projectId, id);
    final thumbFile = await _attachmentFile(projectId, id, thumb: true);
    await fullFile.writeAsBytes(processed.fullBytes, flush: true);
    await thumbFile.writeAsBytes(processed.thumbBytes, flush: true);

    return CardAttachment(
      id: id,
      fileName: fileName,
      mimeType: 'image/jpeg',
      order: order,
      createdAt: now,
      width: processed.width,
      height: processed.height,
    );
  }

  @override
  Future<CardFileAttachment> saveFile({
    required String projectId,
    required Uint8List sourceBytes,
    required String fileName,
    required int order,
    int? createdAt,
  }) async {
    final id = const Uuid().v4();
    final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    await _attachmentsDir(projectId);

    final file = await _fileAttachmentFile(projectId, id);
    await file.writeAsBytes(sourceBytes, flush: true);

    return CardFileAttachment(
      id: id,
      fileName: fileName,
      mimeType: mimeTypeForFileName(fileName),
      order: order,
      createdAt: now,
      size: sourceBytes.length,
    );
  }

  @override
  Future<void> writeBytes({
    required String projectId,
    required String attachmentId,
    required Uint8List bytes,
    bool thumb = false,
  }) async {
    await _attachmentsDir(projectId);
    final file = await _attachmentFile(projectId, attachmentId, thumb: thumb);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> writeFileBytes({
    required String projectId,
    required String attachmentId,
    required Uint8List bytes,
  }) async {
    await _attachmentsDir(projectId);
    final file = await _fileAttachmentFile(projectId, attachmentId);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List?> readBytes({
    required String projectId,
    required String attachmentId,
    bool thumb = false,
  }) async {
    final file = await _attachmentFile(projectId, attachmentId, thumb: thumb);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<Uint8List?> readFileBytes({
    required String projectId,
    required String attachmentId,
  }) async {
    final file = await _fileAttachmentFile(projectId, attachmentId);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<bool> exists({
    required String projectId,
    required String attachmentId,
    bool thumb = false,
  }) async {
    if (thumb) {
      return existsImage(
        projectId: projectId,
        attachmentId: attachmentId,
        thumb: true,
      );
    }
    final imageExists = await existsImage(
      projectId: projectId,
      attachmentId: attachmentId,
    );
    if (imageExists) return true;
    return existsFile(projectId: projectId, attachmentId: attachmentId);
  }

  @override
  Future<bool> existsImage({
    required String projectId,
    required String attachmentId,
    bool thumb = false,
  }) async {
    final file = await _attachmentFile(projectId, attachmentId, thumb: thumb);
    return file.exists();
  }

  @override
  Future<bool> existsFile({
    required String projectId,
    required String attachmentId,
  }) async {
    final file = await _fileAttachmentFile(projectId, attachmentId);
    return file.exists();
  }

  @override
  Future<String?> localFilePath({
    required String projectId,
    required String attachmentId,
  }) async {
    final file = await _fileAttachmentFile(projectId, attachmentId);
    if (!await file.exists()) return null;
    return file.path;
  }

  @override
  Future<void> deleteAttachment({
    required String projectId,
    required String attachmentId,
  }) async {
    for (final thumb in [false, true]) {
      final file = await _attachmentFile(projectId, attachmentId, thumb: thumb);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  @override
  Future<void> deleteFileAttachment({
    required String projectId,
    required String attachmentId,
  }) async {
    final file = await _fileAttachmentFile(projectId, attachmentId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> deleteAttachments({
    required String projectId,
    required Iterable<CardAttachment> attachments,
  }) async {
    for (final attachment in attachments) {
      await deleteAttachment(projectId: projectId, attachmentId: attachment.id);
    }
  }

  @override
  Future<void> deleteFileAttachments({
    required String projectId,
    required Iterable<CardFileAttachment> attachments,
  }) async {
    for (final attachment in attachments) {
      await deleteFileAttachment(
        projectId: projectId,
        attachmentId: attachment.id,
      );
    }
  }

  @override
  Future<Set<String>> listLocalAttachmentIds(String projectId) async {
    final dir = await _dataDir();
    final attachmentsDir =
        KanbanPathsIo.projectAttachmentsDirectory(dir, projectId);
    if (!await attachmentsDir.exists()) return {};

    final ids = <String>{};
    await for (final entity in attachmentsDir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.jpg')) {
        final base = name.substring(0, name.length - 4);
        if (base.endsWith('_thumb')) continue;
        ids.add(base);
        continue;
      }
      if (name.endsWith('.bin')) {
        ids.add(name.substring(0, name.length - 4));
      }
    }
    return ids;
  }

  @override
  Future<void> deleteOrphans({
    required String projectId,
    required Set<String> keepIds,
  }) async {
    final localIds = await listLocalAttachmentIds(projectId);
    for (final id in localIds) {
      if (keepIds.contains(id)) continue;
      await deleteAttachment(projectId: projectId, attachmentId: id);
      await deleteFileAttachment(projectId: projectId, attachmentId: id);
    }
  }

  Future<Directory> _wallpapersDir() async {
    final dir = await _dataDir();
    final wallpapersDir = KanbanPathsIo.wallpapersDirectory(dir);
    if (!await wallpapersDir.exists()) {
      await wallpapersDir.create(recursive: true);
    }
    return wallpapersDir;
  }

  Future<File> _wallpaperFile(String id, {bool thumb = false}) async {
    final dir = await _dataDir();
    return KanbanPathsIo.wallpaperFile(dir, id, thumb: thumb);
  }

  @override
  Future<WallpaperAsset> saveWallpaper({
    required Uint8List sourceBytes,
    required String fileName,
    int? createdAt,
  }) async {
    final processed = processAttachmentImage(sourceBytes);
    if (processed == null) throw StateError('无法解析图片');
    final id = const Uuid().v4();
    final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    await _wallpapersDir();
    await (await _wallpaperFile(id))
        .writeAsBytes(processed.fullBytes, flush: true);
    await (await _wallpaperFile(id, thumb: true))
        .writeAsBytes(processed.thumbBytes, flush: true);
    return WallpaperAsset(
      id: id,
      fileName: fileName,
      width: processed.width,
      height: processed.height,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> writeWallpaperBytes({
    required String wallpaperId,
    required Uint8List bytes,
    bool thumb = false,
  }) async {
    await _wallpapersDir();
    await (await _wallpaperFile(wallpaperId, thumb: thumb))
        .writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List?> readWallpaperBytes(
    String wallpaperId, {
    bool thumb = false,
  }) async {
    final file = await _wallpaperFile(wallpaperId, thumb: thumb);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<bool> wallpaperExists(String wallpaperId,
          {bool thumb = false}) async =>
      (await _wallpaperFile(wallpaperId, thumb: thumb)).exists();

  @override
  Future<void> deleteWallpaper(String wallpaperId) async {
    for (final thumb in const [false, true]) {
      final file = await _wallpaperFile(wallpaperId, thumb: thumb);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<Set<String>> listLocalWallpaperIds() async {
    final dir = await _wallpapersDir();
    final ids = <String>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.jpg') || name.endsWith('_thumb.jpg')) continue;
      ids.add(name.substring(0, name.length - 4));
    }
    return ids;
  }

  @override
  Future<void> deleteOrphanWallpapers(Set<String> keepIds) async {
    for (final id in await listLocalWallpaperIds()) {
      if (!keepIds.contains(id)) await deleteWallpaper(id);
    }
  }

  Future<File> _attachmentFile(
    String projectId,
    String attachmentId, {
    bool thumb = false,
  }) async {
    final dir = await _dataDir();
    return KanbanPathsIo.projectAttachmentFile(
      dir,
      projectId,
      attachmentId,
      thumb: thumb,
    );
  }

  Future<File> _fileAttachmentFile(
    String projectId,
    String attachmentId,
  ) async {
    final dir = await _dataDir();
    return KanbanPathsIo.projectFileAttachmentFile(
      dir,
      projectId,
      attachmentId,
    );
  }
}
