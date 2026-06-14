import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/kanban_models.dart';
import '../../storage/kanban_paths_io.dart';
import 'attachment_image_processor.dart';
import 'attachment_store.dart';

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
  Future<bool> exists({
    required String projectId,
    required String attachmentId,
    bool thumb = false,
  }) async {
    final file = await _attachmentFile(projectId, attachmentId, thumb: thumb);
    return file.exists();
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
  Future<void> deleteAttachments({
    required String projectId,
    required Iterable<CardAttachment> attachments,
  }) async {
    for (final attachment in attachments) {
      await deleteAttachment(projectId: projectId, attachmentId: attachment.id);
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
      if (!name.endsWith('.jpg')) continue;
      final base = name.substring(0, name.length - 4);
      if (base.endsWith('_thumb')) continue;
      ids.add(base);
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
}
