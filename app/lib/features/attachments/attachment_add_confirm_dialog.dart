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
  final noun = isImage ? 'images' : 'files';
  final title =
      analysis.canForceSubmit ? 'Attachment limits' : 'Cannot add $noun';

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
                    ? 'Some items have issues. Cancel to add none of these $noun.'
                    : 'These items cannot be added. Fix the issues and try again.',
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
            onPressed: () =>
                Navigator.pop(ctx, AttachmentAddDecision.cancelled),
            child: const Text('Cancel'),
          ),
          if (analysis.canForceSubmit)
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, AttachmentAddDecision.forceSubmit),
              child: const Text('Add anyway'),
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
      title: const Text('Add anyway?'),
      content: Text(forceSubmitConfirmMessage(analysis)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Add'),
        ),
      ],
    ),
  ).then((value) => value == true);
}
