import 'package:flutter/material.dart';
import 'package:reorderables/reorderables.dart';

import '../../models/kanban_models.dart';
import 'card_attachment_image.dart';

/// 可拖拽排序的卡片图片网格
class CardAttachmentReorderGrid extends StatelessWidget {
  const CardAttachmentReorderGrid({
    super.key,
    required this.attachments,
    required this.missingAttachmentIds,
    required this.onReorder,
    required this.onTap,
    required this.onLongPress,
  });

  final List<CardAttachment> attachments;
  final Set<String> missingAttachmentIds;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onTap;
  final void Function(int index) onLongPress;

  @override
  Widget build(BuildContext context) {
    return ReorderableWrap(
      spacing: 8,
      runSpacing: 8,
      onReorder: onReorder,
      needsLongPressDraggable: true,
      children: [
        for (var index = 0; index < attachments.length; index++)
          _AttachmentTile(
            key: ValueKey(attachments[index].id),
            attachment: attachments[index],
            isCover: index == 0,
            isMissing: missingAttachmentIds.contains(attachments[index].id),
            onTap: () => onTap(index),
            onLongPress: () => onLongPress(index),
          ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    super.key,
    required this.attachment,
    required this.isCover,
    required this.isMissing,
    required this.onTap,
    required this.onLongPress,
  });

  final CardAttachment attachment;
  final bool isCover;
  final bool isMissing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 104,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CardAttachmentImage(
              attachmentId: attachment.id,
              borderRadius: BorderRadius.circular(8),
              showMissingLabel: isMissing,
            ),
            if (isCover)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '封面',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Icon(
                Icons.drag_indicator,
                size: 16,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
