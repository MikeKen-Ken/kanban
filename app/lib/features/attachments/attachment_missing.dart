import '../../models/kanban_models.dart';
import '../project/project_settings.dart';
import '../trash/trash_models.dart';
import 'attachment_refs.dart';
import 'attachment_store.dart';

/// 扫描引用存在但本地文件缺失的附件 id
Future<Set<String>> findMissingAttachmentIds({
  required AttachmentStore? store,
  required String projectId,
  required KanbanBoard board,
  required TrashBin trash,
  ProjectSettings? settings,
}) async {
  if (store == null) return {};

  final refs = collectReferencedAttachmentsByKind(
    board,
    trash,
    settings: settings,
  );
  final missing = <String>{};
  for (final id in refs.imageIds) {
    final exists = await store.existsImage(
      projectId: projectId,
      attachmentId: id,
    );
    if (!exists) {
      missing.add(id);
    }
  }
  for (final id in refs.fileIds) {
    final exists = await store.existsFile(
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
  for (final attachment in card.fileAttachments) {
    if (missingIds.contains(attachment.id)) {
      count++;
    }
  }
  return count;
}
