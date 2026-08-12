import 'package:flutter/material.dart';

import 'attachment_add_validation.dart';

/// 用户在不合规提醒中的选择。
enum AttachmentAddDecision {
  cancelled,
  forceSubmit,
}

/// 展示不合规说明，并提供取消 / 执意提交（若允许）。
Future<AttachmentAddDecision?> showAttachmentAddIssueDialog(
  BuildContext context, {
  required AttachmentAddAnalysis analysis,
  required bool isImage,
}) {
  final noun = isImage ? '图片' : '文件';
  final title = analysis.canForceSubmit ? '附件不符合推荐限制' : '无法添加$noun';

  return showDialog<AttachmentAddDecision>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                analysis.canForceSubmit
                    ? '以下内容存在问题，取消将不会添加任何$noun：'
                    : '以下内容无法添加，请调整后重试：',
              ),
              const SizedBox(height: 12),
              for (final issue in analysis.issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        issue.canForceSubmit
                            ? Icons.warning_amber_outlined
                            : Icons.error_outline,
                        size: 18,
                        color: issue.canForceSubmit
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              issue.label,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              issue.reason,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, AttachmentAddDecision.cancelled),
            child: const Text('取消'),
          ),
          if (analysis.canForceSubmit)
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, AttachmentAddDecision.forceSubmit),
              child: const Text('执意提交'),
            ),
        ],
      );
    },
  );
}

/// 执意提交前的二次确认。
Future<bool> showAttachmentAddForceConfirmDialog(
  BuildContext context, {
  required AttachmentAddAnalysis analysis,
}) {
  return showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认执意提交？'),
          content: Text(forceSubmitConfirmMessage(analysis)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认添加'),
            ),
          ],
        ),
      ).then((value) => value == true);
}
