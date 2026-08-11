import '../../models/kanban_models.dart';
import '../project/project_settings.dart';
import '../trash/trash_models.dart';

/// 被引用的附件 id，按图片与通用文件分组。
class ReferencedAttachmentIds {
  const ReferencedAttachmentIds({
    required this.imageIds,
    required this.fileIds,
  });

  final Set<String> imageIds;
  final Set<String> fileIds;

  Set<String> get all => {...imageIds, ...fileIds};
}

void _collectFromCard(KanbanCard card, Set<String> imageIds, Set<String> fileIds) {
  for (final attachment in card.attachments) {
    imageIds.add(attachment.id);
  }
  for (final attachment in card.fileAttachments) {
    fileIds.add(attachment.id);
  }
}

/// 从看板、回收站与项目设置收集所有被引用的附件 id
Set<String> collectReferencedAttachmentIds(
  KanbanBoard board,
  TrashBin trash, {
  ProjectSettings? settings,
  String? backgroundAttachmentId,
}) {
  return collectReferencedAttachmentsByKind(
    board,
    trash,
    settings: settings,
    backgroundAttachmentId: backgroundAttachmentId,
  ).all;
}

ReferencedAttachmentIds collectReferencedAttachmentsByKind(
  KanbanBoard board,
  TrashBin trash, {
  ProjectSettings? settings,
  String? backgroundAttachmentId,
}) {
  final imageIds = <String>{};
  final fileIds = <String>{};
  for (final col in board.columns) {
    for (final card in col.cards) {
      _collectFromCard(card, imageIds, fileIds);
    }
  }
  for (final item in trash.items) {
    final card = item.cardPayload;
    if (card != null) {
      _collectFromCard(card, imageIds, fileIds);
      continue;
    }
    final column = item.columnPayload;
    if (column == null) continue;
    for (final card in column.cards) {
      _collectFromCard(card, imageIds, fileIds);
    }
  }

  final hasSharedWallpapers = settings?.wallpaperIds.isNotEmpty == true;
  final bgId = hasSharedWallpapers
      ? null
      : (backgroundAttachmentId ?? settings?.backgroundAttachmentId);
  if (bgId != null && bgId.isNotEmpty) {
    imageIds.add(bgId);
  }
  return ReferencedAttachmentIds(imageIds: imageIds, fileIds: fileIds);
}
