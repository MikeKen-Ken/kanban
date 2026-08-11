import 'dart:typed_data';

import '../../models/kanban_models.dart';
import '../project/project_settings.dart';
import '../trash/trash_models.dart';
import 'attachment_refs.dart';
import 'attachment_store.dart';

/// WebDAV 同步使用的附件读写端口
class AttachmentSyncAdapter {
  AttachmentSyncAdapter(this._storage);

  final AttachmentStore? _storage;

  bool get isAvailable => _storage != null;

  Set<String> referencedIds(
    KanbanBoard board,
    TrashBin trash, {
    ProjectSettings? settings,
  }) =>
      collectReferencedAttachmentIds(board, trash, settings: settings);

  ReferencedAttachmentIds referencedIdsByKind(
    KanbanBoard board,
    TrashBin trash, {
    ProjectSettings? settings,
  }) =>
      collectReferencedAttachmentsByKind(board, trash, settings: settings);

  Future<Uint8List?> readFile(
    String projectId,
    String attachmentId, {
    bool thumb = false,
    bool isFileAttachment = false,
  }) async {
    final storage = _storage;
    if (storage == null) return null;
    if (isFileAttachment) {
      return storage.readFileBytes(
        projectId: projectId,
        attachmentId: attachmentId,
      );
    }
    return storage.readBytes(
      projectId: projectId,
      attachmentId: attachmentId,
      thumb: thumb,
    );
  }

  Future<void> writeFile(
    String projectId,
    String attachmentId,
    Uint8List bytes, {
    bool thumb = false,
    bool isFileAttachment = false,
  }) async {
    final storage = _storage;
    if (storage == null) return;
    if (isFileAttachment) {
      await storage.writeFileBytes(
        projectId: projectId,
        attachmentId: attachmentId,
        bytes: bytes,
      );
      return;
    }
    await storage.writeBytes(
      projectId: projectId,
      attachmentId: attachmentId,
      bytes: bytes,
      thumb: thumb,
    );
  }

  Future<bool> exists(
    String projectId,
    String attachmentId, {
    bool thumb = false,
    bool isFileAttachment = false,
  }) async {
    final storage = _storage;
    if (storage == null) return false;
    if (isFileAttachment) {
      return storage.existsFile(
        projectId: projectId,
        attachmentId: attachmentId,
      );
    }
    return storage.existsImage(
      projectId: projectId,
      attachmentId: attachmentId,
      thumb: thumb,
    );
  }

  Future<Set<String>> listLocalIds(String projectId) async {
    final storage = _storage;
    if (storage == null) return {};
    return storage.listLocalAttachmentIds(projectId);
  }

  Future<void> deleteOrphans(String projectId, Set<String> keepIds) async {
    final storage = _storage;
    if (storage == null) return;
    await storage.deleteOrphans(projectId: projectId, keepIds: keepIds);
  }

  Future<Uint8List?> readWallpaper(String id, {bool thumb = false}) =>
      _storage?.readWallpaperBytes(id, thumb: thumb) ??
      Future<Uint8List?>.value(null);

  Future<void> writeWallpaper(
    String id,
    Uint8List bytes, {
    bool thumb = false,
  }) async =>
      _storage?.writeWallpaperBytes(
        wallpaperId: id,
        bytes: bytes,
        thumb: thumb,
      );

  Future<bool> wallpaperExists(String id, {bool thumb = false}) =>
      _storage?.wallpaperExists(id, thumb: thumb) ?? Future.value(false);

  Future<void> deleteOrphanWallpapers(Set<String> keepIds) async =>
      _storage?.deleteOrphanWallpapers(keepIds);
}
