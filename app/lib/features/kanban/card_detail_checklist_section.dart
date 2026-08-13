import 'package:flutter/material.dart';

import '../../models/kanban_models.dart';
import 'edit_checklist_item.dart';

/// 弹出编辑对话框并写回清单项；返回更新后的列表（无变更则返回原列表）。
Future<List<ChecklistItem>> editChecklistLikeItem({
  required BuildContext context,
  required String id,
  required List<ChecklistItem> items,
  required String dialogTitle,
}) async {
  final current = items.where((item) => item.id == id).firstOrNull;
  if (current == null) return items;
  final controller = TextEditingController(text: current.text);
  final dialogResult = await showDialog<Object?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(dialogTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () {
            // 清空后点取消视为删除；文本非空则明确丢弃编辑
            final text = controller.text.trim();
            Navigator.pop(
              ctx,
              text.isEmpty ? '' : checklistItemEditCancelled,
            );
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  final nextText = resolveChecklistItemDialogResult(
    dialogResult: dialogResult,
    draftText: controller.text,
  );
  controller.dispose();
  if (!context.mounted) return items;
  return applyChecklistItemEdit(
    items: items,
    id: id,
    dialogResult: nextText,
  );
}

/// 子任务与验证反馈列表 UI。
class CardDetailChecklistSection extends StatelessWidget {
  const CardDetailChecklistSection({
    super.key,
    required this.checklist,
    required this.verificationFeedback,
    required this.checklistInput,
    required this.verificationFeedbackInput,
    required this.onAddChecklistItem,
    required this.onToggleChecklistItem,
    required this.onRemoveChecklistItem,
    required this.onEditChecklistItem,
    required this.onAddVerificationFeedbackItem,
    required this.onToggleVerificationFeedbackItem,
    required this.onRemoveVerificationFeedbackItem,
    required this.onEditVerificationFeedbackItem,
  });

  final List<ChecklistItem> checklist;
  final List<ChecklistItem> verificationFeedback;
  final TextEditingController checklistInput;
  final TextEditingController verificationFeedbackInput;
  final VoidCallback onAddChecklistItem;
  final ValueChanged<String> onToggleChecklistItem;
  final ValueChanged<String> onRemoveChecklistItem;
  final ValueChanged<String> onEditChecklistItem;
  final VoidCallback onAddVerificationFeedbackItem;
  final ValueChanged<String> onToggleVerificationFeedbackItem;
  final ValueChanged<String> onRemoveVerificationFeedbackItem;
  final ValueChanged<String> onEditVerificationFeedbackItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('子任务', style: theme.textTheme.titleSmall),
            if (checklist.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '${checklist.where((i) => i.completed).length}/${checklist.length}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ...checklist.map(
          (item) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: item.completed,
            title: GestureDetector(
              onTap: () => onEditChecklistItem(item.id),
              child: Text(
                item.text,
                style: item.completed
                    ? const TextStyle(
                        decoration: TextDecoration.lineThrough,
                      )
                    : null,
              ),
            ),
            onChanged: (_) => onToggleChecklistItem(item.id),
            secondary: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => onRemoveChecklistItem(item.id),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('card-detail-checklist'),
                controller: checklistInput,
                decoration: const InputDecoration(
                  hintText: '添加子任务…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => onAddChecklistItem(),
              ),
            ),
            IconButton(
              onPressed: onAddChecklistItem,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text('验证反馈', style: theme.textTheme.titleSmall),
            if (verificationFeedback.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '${verificationFeedback.where((i) => i.completed).length}/${verificationFeedback.length}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ...verificationFeedback.map(
          (item) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: item.completed,
            title: GestureDetector(
              onTap: () => onEditVerificationFeedbackItem(item.id),
              child: Text(
                item.text,
                style: item.completed
                    ? const TextStyle(
                        decoration: TextDecoration.lineThrough,
                      )
                    : null,
              ),
            ),
            onChanged: (_) => onToggleVerificationFeedbackItem(item.id),
            secondary: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => onRemoveVerificationFeedbackItem(item.id),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('card-detail-verification-feedback'),
                controller: verificationFeedbackInput,
                decoration: const InputDecoration(
                  hintText: '添加验证反馈…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => onAddVerificationFeedbackItem(),
              ),
            ),
            IconButton(
              onPressed: onAddVerificationFeedbackItem,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
