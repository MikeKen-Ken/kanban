import 'dart:typed_data';

import '../../models/kanban_models.dart';
import '../trash/trash_models.dart';
import 'attachment_refs.dart';
import 'attachment_store.dart';

/// 扫描引用存在但本地文件缺失的附件 id
Future<Set<String>> findMissingAttachmentIds({
  required AttachmentStore? store,
  required String projectId,
  required KanbanBoard board,
  required TrashBin trash,
}) async {
  if (store == null) return {};

  final ids = collectReferencedAttachmentIds(board, trash);
  final missing = <String>{};
  for (final id in ids) {
    final exists = await store.exists(
      projectId: projectId,
      attachmentId: id,
    );
    if (!exists) {
      missing.add(id);
    }
  }
  return missing;
}

int countMissingAttachmentsForCard(
  KanbanCard card,
  Set<String> missingIds,
) {
  var count = 0;
  for (final attachment in card.attachments) {
    if (missingIds.contains(attachment.id)) {
      count++;
    }
  }
  return count;
}
