import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../settings/column_color_picker.dart';
import '../kanban/kanban_labels.dart';
import '../project/project_theme.dart';
import '../../common/app_snack_bar.dart';

class LabelManagementScreen extends StatelessWidget {
  const LabelManagementScreen({super.key});

  Future<({String name, int colorValue})?> _editLabel(
    BuildContext context, {
    KanbanLabel? label,
  }) async {
    final controller = context.read<BoardController>();
    final nameController = TextEditingController(text: label?.name ?? '');
    var colorValue = label?.colorValue ??
        projectThemeForId(controller.projectSettings.themeId)
            .defaultLabelColor
            .toARGB32();

    final result = await showDialog<({String name, int colorValue})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(label == null ? '新建标签' : '编辑标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '标签名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(colorValue),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await showColumnColorPicker(
                        context: context,
                        currentColorValue: colorValue,
                        title: '标签颜色',
                        allowDefault: false,
                      );
                      if (picked != null) {
                        setDialogState(() => colorValue = picked);
                      }
                    },
                    icon: const Icon(Icons.palette_outlined),
                    label: const Text('选择颜色'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  (name: name, colorValue: colorValue),
                );
              },
              child: Text(label == null ? '创建' : '保存'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    return result;
  }

  Future<void> _create(BuildContext context) async {
    final result = await _editLabel(context);
    if (result == null || !context.mounted) return;
    await context
        .read<BoardController>()
        .addCustomLabel(result.name, result.colorValue);
    if (!context.mounted) return;
    showAppSnackBar(context, message: '已创建标签「${result.name}」');
  }

  Future<void> _update(BuildContext context, KanbanLabel label) async {
    final result = await _editLabel(context, label: label);
    if (result == null || !context.mounted) return;
    final updated = await context.read<BoardController>().updateCustomLabel(
          label.key,
          name: result.name,
          colorValue: result.colorValue,
        );
    if (!context.mounted) return;
    showAppSnackBar(context, message: updated ? '标签已更新' : '标签不存在，无法更新');
  }

  Future<void> _delete(BuildContext context, KanbanLabel label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除标签？'),
        content: Text(
          '「${label.name}」将移入回收站。已有卡片中的标签引用不会自动替换。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<BoardController>().removeCustomLabel(label.key);
    if (!context.mounted) return;
    showAppSnackBar(context, message: '已删除标签「${label.name}」');
  }

  Widget _presetLabelChip(KanbanLabel label) {
    return Chip(
      label: Text(label.name),
      backgroundColor: label.color.withValues(alpha: 0.12),
      side: BorderSide(color: label.color.withValues(alpha: 0.35)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _customLabelChip(BuildContext context, KanbanLabel label) {
    return InputChip(
      label: Text(label.name),
      backgroundColor: label.color.withValues(alpha: 0.12),
      side: BorderSide(color: label.color.withValues(alpha: 0.35)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
      avatar: CircleAvatar(backgroundColor: label.color, radius: 8),
      onPressed: () => _update(context, label),
      deleteIcon: Icon(
        Icons.close,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onDeleted: () => _delete(context, label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BoardController>(
      builder: (context, controller, _) {
        final presetLabels = presetKanbanLabels(
          controller.projectSettings.themeId,
        );
        final customLabels = controller.appSettings.customLabels;
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('标签管理'),
            actions: [
              IconButton(
                tooltip: '新建标签',
                onPressed: () => _create(context),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            children: [
              Text('预置标签', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                '内置标签，不可编辑或删除',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in presetLabels) _presetLabelChip(label),
                ],
              ),
              const SizedBox(height: 24),
              Text('自定义标签', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              if (customLabels.isEmpty)
                Text(
                  '还没有自定义标签',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final label in customLabels)
                      _customLabelChip(context, label),
                  ],
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: const Text('新建标签'),
          ),
        );
      },
    );
  }
}
