import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../../settings/column_color_picker.dart';
import '../kanban/kanban_labels.dart';
import '../project/project_theme.dart';

Future<({String name, int colorValue})?> showLabelFormDialog(
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

Future<void> _createLabel(BuildContext context) async {
  final result = await showLabelFormDialog(context);
  if (result == null || !context.mounted) return;
  await context
      .read<BoardController>()
      .addCustomLabel(result.name, result.colorValue);
  if (!context.mounted) return;
  showAppSnackBar(context, message: '已创建标签「${result.name}」');
}

Future<void> _updateLabel(BuildContext context, KanbanLabel label) async {
  final result = await showLabelFormDialog(context, label: label);
  if (result == null || !context.mounted) return;
  final updated = await context.read<BoardController>().updateCustomLabel(
        label.key,
        name: result.name,
        colorValue: result.colorValue,
      );
  if (!context.mounted) return;
  showAppSnackBar(context, message: updated ? '标签已更新' : '标签不存在，无法更新');
}

Future<void> _deleteLabel(BuildContext context, KanbanLabel label) async {
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

/// 标签编辑界面：集中提供「新增 / 编辑 / 删除」自定义标签操作。
Future<void> showLabelEditorDialog(BuildContext context) async {
  final controller = context.read<BoardController>();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final customLabels = controller.appSettings.customLabels;
        return AlertDialog(
          title: const Text('编辑标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (customLabels.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '还没有自定义标签',
                    style: Theme.of(dialogContext).textTheme.bodyMedium
                        ?.copyWith(
                          color: Theme.of(dialogContext)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                )
              else
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final label in customLabels)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: label.color,
                              radius: 10,
                            ),
                            title: Text(label.name),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: '编辑「${label.name}」',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () async {
                                    await _updateLabel(context, label);
                                    setDialogState(() {});
                                  },
                                ),
                                IconButton(
                                  tooltip: '删除「${label.name}」',
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color:
                                        Theme.of(dialogContext).colorScheme.error,
                                  ),
                                  onPressed: () async {
                                    await _deleteLabel(context, label);
                                    setDialogState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await _createLabel(context);
                setDialogState(() {});
              },
              icon: const Icon(Icons.add),
              label: const Text('新增标签'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('完成'),
            ),
          ],
        );
      },
    ),
  );
}
