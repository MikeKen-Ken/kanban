import '../../models/kanban_models.dart';
import '../trash/trash_models.dart';

/// 从看板与回收站收集所有被引用的附件 id
Set<String> collectReferencedAttachmentIds(
  KanbanBoard board,
  TrashBin trash,
) {
  final ids = <String>{};
  for (final col in board.columns) {
    for (final card in col.cards) {
      for (final attachment in card.attachments) {
        ids.add(attachment.id);
      }
    }
  }
  for (final item in trash.items) {
    final card = item.cardPayload;
    if (card != null) {
      for (final attachment in card.attachments) {
        ids.add(attachment.id);
      }
      continue;
    }
    final column = item.columnPayload;
    if (column == null) continue;
    for (final card in column.cards) {
      for (final attachment in card.attachments) {
        ids.add(attachment.id);
      }
    }
  }
  return ids;
}
