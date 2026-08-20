import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../attachments/attachment_add_flow.dart';
import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';

String formatFileAttachmentSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData iconForFileAttachment(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot >= fileName.length - 1) {
    return Icons.insert_drive_file_outlined;
  }
  return switch (fileName.substring(dot + 1).toLowerCase()) {
    'txt' || 'md' || 'markdown' => Icons.description_outlined,
    'pdf' => Icons.picture_as_pdf_outlined,
    'json' || 'yaml' || 'yml' || 'xml' => Icons.data_object_outlined,
    'dart' ||
    'js' ||
    'ts' ||
    'py' ||
    'sh' ||
    'ps1' ||
    'bat' ||
    'cmd' =>
      Icons.terminal_outlined,
    'zip' => Icons.folder_zip_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

/// 卡片通用文件附件区块：脚本、文档、TXT 等。
class CardDetailFileAttachmentsSection extends StatelessWidget {
  const CardDetailFileAttachmentsSection({
    super.key,
    required this.columnId,
    required this.cardId,
    required this.attachments,
    required this.missingAttachmentIds,
    required this.onAttachmentsChanged,
  });

  final String columnId;
  final String cardId;
  final List<CardFileAttachment> attachments;
  final Set<String> missingAttachmentIds;
  final ValueChanged<List<CardFileAttachment>> onAttachmentsChanged;

  int get _missingCount {
    var count = 0;
    for (final attachment in attachments) {
      if (missingAttachmentIds.contains(attachment.id)) count++;
    }
    return count;
  }

  Future<void> _pickFiles(BuildContext context) async {
    if (attachments.length >= KanbanCard.maxFileAttachments) {
      showAppSnackBar(
        context,
        message: '每张卡片最多 ${KanbanCard.maxFileAttachments} 个文件',
      );
      return;
    }

    final controller = context.read<BoardController>();
    final error = await runCardFileAttachmentAddFlow(
      context: context,
      controller: controller,
      columnId: columnId,
      cardId: cardId,
      currentCount: attachments.length,
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
      onAttachmentsChanged([...updated.sortedFileAttachments]);
    }
  }

  Future<void> _openAttachment(
    BuildContext context,
    CardFileAttachment attachment,
  ) async {
    final error = await context.read<BoardController>().openCardFileAttachment(
          columnId,
          cardId,
          attachment.id,
        );
    if (!context.mounted || error == null) return;
    showAppSnackBar(context, message: error);
  }

  Future<void> _openAttachmentDirectory(
    BuildContext context,
    CardFileAttachment attachment,
  ) async {
    final error =
        await context.read<BoardController>().openCardFileAttachmentDirectory(
              columnId,
              cardId,
              attachment.id,
            );
    if (!context.mounted || error == null) return;
    showAppSnackBar(context, message: error);
  }

  Future<void> _removeAttachment(
    BuildContext context,
    String attachmentId,
  ) async {
    onAttachmentsChanged(
      attachments.where((item) => item.id != attachmentId).toList(),
    );
    await context.read<BoardController>().removeCardFileAttachment(
          columnId,
          cardId,
          attachmentId,
        );
    if (!context.mounted) return;
    final updated = context
        .read<BoardController>()
        .board
        ?.columns
        .where((col) => col.id == columnId)
        .expand((col) => col.cards)
        .where((card) => card.id == cardId)
        .firstOrNull;
    if (updated != null) {
      onAttachmentsChanged([...updated.sortedFileAttachments]);
    }
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
            Text('文件', style: theme.textTheme.titleSmall),
            const Spacer(),
            Text(
              '${attachments.length}/${KanbanCard.maxFileAttachments}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (missingCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MaterialBanner(
              content: Text('有 $missingCount 个文件未下载到本机，请检查同步'),
              leading: Icon(
                Icons.cloud_off_outlined,
                color: theme.colorScheme.error,
              ),
              actions: [
                TextButton(
                  onPressed: () => context.read<BoardController>().mergeNow(),
                  child: const Text('合并同步'),
                ),
              ],
            ),
          ),
        if (attachments.isNotEmpty)
          ...attachments.map(
            (attachment) {
              final missing = missingAttachmentIds.contains(attachment.id);
              final sizeLabel = formatFileAttachmentSize(attachment.size);
              return Card.outlined(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(iconForFileAttachment(attachment.fileName)),
                  title: Text(
                    attachment.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: missing
                      ? Text(
                          '尚未同步到本机',
                          style: TextStyle(color: theme.colorScheme.error),
                        )
                      : sizeLabel.isEmpty
                          ? null
                          : Text(sizeLabel),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'open') {
                        await _openAttachment(context, attachment);
                      } else if (action == 'directory') {
                        await _openAttachmentDirectory(context, attachment);
                      } else if (action == 'delete') {
                        await _removeAttachment(context, attachment.id);
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (!missing)
                        const PopupMenuItem(
                          value: 'open',
                          child: ListTile(
                            leading: Icon(Icons.open_in_new_outlined),
                            title: Text('打开'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (!missing)
                        const PopupMenuItem(
                          value: 'directory',
                          child: ListTile(
                            leading: Icon(Icons.folder_open_outlined),
                            title: Text('打开所在文件夹'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            '删除文件',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  onTap: missing
                      ? null
                      : () => _openAttachment(context, attachment),
                ),
              );
            },
          ),
        FilledButton.tonalIcon(
          onPressed: attachments.length >= KanbanCard.maxFileAttachments
              ? null
              : () => _pickFiles(context),
          icon: const Icon(Icons.attach_file_outlined, size: 18),
          label: const Text('添加文件'),
        ),
      ],
    );
  }
}
