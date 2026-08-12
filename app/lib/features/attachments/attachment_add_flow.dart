import 'package:flutter/material.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import 'attachment_add_confirm_dialog.dart';
import 'attachment_add_validation.dart';
import 'attachment_image_processor.dart';
import 'card_file_picker.dart';
import 'card_image_picker.dart';

/// 卡片文件附件：选择 → 合规检查 → 弹窗确认 → 提交。
Future<String?> runCardFileAttachmentAddFlow({
  required BuildContext context,
  required BoardController controller,
  required String columnId,
  required String cardId,
  required int currentCount,
}) async {
  final picked = await pickCardFiles();
  if (picked.isEmpty) return null;

  final analysis = analyzeFileAttachmentPicks(
    picked: picked,
    currentCount: currentCount,
    maxCount: KanbanCard.maxFileAttachments,
  );

  var allowOversized = false;
  var filesToAdd = picked;

  if (analysis.hasIssues) {
    if (!context.mounted) return null;
    final decision = await showAttachmentAddIssueDialog(
      context,
      analysis: analysis,
      isImage: false,
    );
    if (decision != AttachmentAddDecision.forceSubmit) return null;

    if (!context.mounted) return null;
    final confirmed = await showAttachmentAddForceConfirmDialog(
      context,
      analysis: analysis,
    );
    if (!confirmed) return null;

    allowOversized = true;
    final remaining = KanbanCard.maxFileAttachments - currentCount;
    filesToAdd = trimPickedAttachmentsForAdd(picked, remaining);
    if (filesToAdd.isEmpty) return null;
  }

  return controller.addCardFileAttachments(
    columnId,
    cardId,
    pickFiles: () async => filesToAdd,
    allowOversized: allowOversized,
  );
}

/// 卡片图片附件：选择 → 合规检查 → 弹窗确认 → 提交。
Future<String?> runCardImageAttachmentAddFlow({
  required BuildContext context,
  required BoardController controller,
  required String columnId,
  required String cardId,
  required int currentCount,
  required CardImageAddSource source,
}) async {
  final picked = await pickImagesForSource(source);
  if (picked.isEmpty) {
    return switch (source) {
      CardImageAddSource.clipboard => '剪贴板中没有图片',
      _ => null,
    };
  }

  final analysis = analyzeImageAttachmentPicks(
    picked: picked,
    currentCount: currentCount,
    maxCount: KanbanCard.maxAttachments,
  );

  var imagesToAdd = picked;

  if (analysis.hasIssues) {
    if (!context.mounted) return null;
    final decision = await showAttachmentAddIssueDialog(
      context,
      analysis: analysis,
      isImage: true,
    );
    if (decision != AttachmentAddDecision.forceSubmit) return null;

    if (!context.mounted) return null;
    final confirmed = await showAttachmentAddForceConfirmDialog(
      context,
      analysis: analysis,
    );
    if (!confirmed) return null;

    final remaining = KanbanCard.maxAttachments - currentCount;
    imagesToAdd = [
      for (final image in trimPickedAttachmentsForAdd(picked, remaining))
        if (processAttachmentImage(image.bytes) != null) image,
    ];
    if (imagesToAdd.isEmpty) return null;
  }

  return controller.addCardAttachments(
    columnId,
    cardId,
    pickImages: () async => imagesToAdd,
  );
}
