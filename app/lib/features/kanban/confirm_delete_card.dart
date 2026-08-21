import 'package:flutter/material.dart';

/// 按本机偏好决定是否继续删除卡片。
///
/// [confirmBeforeDelete] 为 false 时直接允许删除（进入回收站）；
/// 为 true 时调用 [prompt]，仅当返回 `true` 时继续。
Future<bool> resolveCardDeleteConfirmation({
  required bool confirmBeforeDelete,
  required Future<bool?> Function() prompt,
}) async {
  if (!confirmBeforeDelete) return true;
  return (await prompt()) == true;
}

/// 展示「删除卡片？」确认对话框，返回用户是否确认。
Future<bool?> showDeleteCardConfirmDialog({
  required BuildContext context,
  required String cardTitle,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete card?'),
      content: Text('"$cardTitle" will be moved to Trash'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

/// 右键删除与详情删除共用：按偏好决定是否弹确认，再决定是否继续删除。
Future<bool> confirmDeleteCardIfNeeded({
  required BuildContext context,
  required String cardTitle,
  required bool confirmBeforeDelete,
}) {
  return resolveCardDeleteConfirmation(
    confirmBeforeDelete: confirmBeforeDelete,
    prompt: () => showDeleteCardConfirmDialog(
      context: context,
      cardTitle: cardTitle,
    ),
  );
}
