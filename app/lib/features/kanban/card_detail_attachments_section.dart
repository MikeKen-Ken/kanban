import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../attachments/attachment_add_flow.dart';
import '../attachments/card_attachment_reorder_grid.dart';
import '../attachments/card_attachment_viewer.dart';
import '../attachments/card_image_add_sheet.dart';

/// 卡片图片附件区块：缺失提示、排序网格与添加入口。
class CardDetailAttachmentsSection extends StatelessWidget {
  const CardDetailAttachmentsSection({
    super.key,
    required this.columnId,
    required this.cardId,
    required this.attachments,
    required this.missingAttachmentIds,
    required this.onAttachmentsChanged,
  });

  final String columnId;
  final String cardId;
  final List<CardAttachment> attachments;
  final Set<String> missingAttachmentIds;
  final ValueChanged<List<CardAttachment>> onAttachmentsChanged;

  int get _missingCount {
    var count = 0;
    for (final attachment in attachments) {
      if (missingAttachmentIds.contains(attachment.id)) count++;
    }
    return count;
  }

  Future<void> _pickAttachments(BuildContext context) async {
    if (attachments.length >= KanbanCard.maxAttachments) {
      showAppSnackBar(
        context,
        message: '每张卡片最多 ${KanbanCard.maxAttachments} 张图片',
      );
      return;
    }

    final source = await showCardImageAddSourceSheet(context);
    if (!context.mounted || source == null) return;

    final controller = context.read<BoardController>();
    final error = await runCardImageAttachmentAddFlow(
      context: context,
      controller: controller,
      columnId: columnId,
      cardId: cardId,
      currentCount: attachments.length,
      source: source,
    );
    if (!context.mounted) return;
    if (error != null) {
      showAppSnackBar(context, message: error);
      return;
    }

    final updated = controller.board?.columns
        .where((col) => col.id == columnId)
        .expand((col) => col.cards)
        .where((card) => card.id == cardId)
        .firstOrNull;
    if (updated != null) {
      onAttachmentsChanged([...updated.sortedAttachments]);
    }
  }

  Future<void> _removeAttachment(
    BuildContext context,
    String attachmentId,
  ) async {
    await context.read<BoardController>().removeCardAttachment(
          columnId,
          cardId,
          attachmentId,
        );
    if (!context.mounted) return;
    onAttachmentsChanged(
      attachments.where((item) => item.id != attachmentId).toList(),
    );
  }

  Future<void> _setCover(BuildContext context, String attachmentId) async {
    await context.read<BoardController>().setCardAttachmentCover(
          columnId,
          cardId,
          attachmentId,
        );
    if (!context.mounted) return;
    final selected = attachments.firstWhere((a) => a.id == attachmentId);
    final others = attachments.where((a) => a.id != attachmentId).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    onAttachmentsChanged([
      selected.copyWith(order: 0),
      for (var i = 0; i < others.length; i++) others[i].copyWith(order: i + 1),
    ]);
  }

  Future<void> _reorderAttachments(
    BuildContext context,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) return;
    final next = [...attachments];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    onAttachmentsChanged(next);
    await context.read<BoardController>().reorderCardAttachments(
          columnId,
          cardId,
          next,
        );
  }

  void _openAttachmentViewer(BuildContext context, int index) {
    showCardAttachmentViewer(
      context: context,
      attachments: attachments,
      initialIndex: index,
      columnId: columnId,
      cardId: cardId,
      onAttachmentsChanged: onAttachmentsChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missingCount = _missingCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('图片', style: theme.textTheme.titleSmall),
            const Spacer(),
            Text(
              '${attachments.length}/${KanbanCard.maxAttachments}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (missingCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MaterialBanner(
              content: Text('有 $missingCount 张图片未下载到本机，请检查同步'),
              leading: Icon(
                Icons.cloud_off_outlined,
                color: theme.colorScheme.error,
              ),
              actions: [
                TextButton(
                  onPressed: () => context.read<BoardController>().syncNow(),
                  child: const Text('立即同步'),
                ),
              ],
            ),
          ),
        if (attachments.isNotEmpty)
          CardAttachmentReorderGrid(
            attachments: attachments,
            missingAttachmentIds: missingAttachmentIds,
            onReorder: (oldIndex, newIndex) =>
                _reorderAttachments(context, oldIndex, newIndex),
            onTap: (index) => _openAttachmentViewer(context, index),
            onLongPress: (index) async {
              final attachment = attachments[index];
              final isCover = index == 0;
              final action = await showModalBottomSheet<String>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isCover)
                        ListTile(
                          leading: const Icon(Icons.photo),
                          title: const Text('设为封面'),
                          onTap: () => Navigator.pop(ctx, 'cover'),
                        ),
                      ListTile(
                        leading: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          '删除图片',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        onTap: () => Navigator.pop(ctx, 'delete'),
                      ),
                    ],
                  ),
                ),
              );
              if (!context.mounted || action == null) return;
              if (action == 'cover') {
                await _setCover(context, attachment.id);
              } else if (action == 'delete') {
                await _removeAttachment(context, attachment.id);
              }
            },
          ),
        const SizedBox(height: 8),
        Text(
          '长按拖动可调整顺序',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: attachments.length >= KanbanCard.maxAttachments
              ? null
              : () => _pickAttachments(context),
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: const Text('添加图片'),
        ),
      ],
    );
  }
}
