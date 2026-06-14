import 'dart:typed_data';

import '../../models/kanban_models.dart';
import '../trash/trash_models.dart';
import 'attachment_refs.dart';
import 'attachment_store.dart';

/// WebDAV 同步使用的附件读写端口
class AttachmentSyncAdapter {
  AttachmentSyncAdapter(this._storage);

  final AttachmentStore? _storage;

  bool get isAvailable => _storage != null;

  Set<String> referencedIds(KanbanBoard board, TrashBin trash) =>
      collectReferencedAttachmentIds(board, trash);

  Future<Uint8List?> readFile(
    String projectId,
    String attachmentId, {
    bool thumb = false,
  }) async {
    final storage = _storage;
    if (storage == null) return null;
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
  }) async {
    final storage = _storage;
    if (storage == null) return;
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
  }) async {
    final storage = _storage;
    if (storage == null) return false;
    return storage.exists(
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
}
