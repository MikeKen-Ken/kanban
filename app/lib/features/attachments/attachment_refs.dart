import '../../models/kanban_models.dart';
import '../project/project_settings.dart';
import '../trash/trash_models.dart';

/// 从看板、回收站与项目设置收集所有被引用的附件 id
Set<String> collectReferencedAttachmentIds(
  KanbanBoard board,
  TrashBin trash, {
  ProjectSettings? settings,
  String? backgroundAttachmentId,
}) {
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

  final hasSharedWallpapers = settings?.wallpaperIds.isNotEmpty == true;
  final bgId = hasSharedWallpapers
      ? null
      : (backgroundAttachmentId ?? settings?.backgroundAttachmentId);
  if (bgId != null && bgId.isNotEmpty) {
    ids.add(bgId);
  }
  return ids;
}
