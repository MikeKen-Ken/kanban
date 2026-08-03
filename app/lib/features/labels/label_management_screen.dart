import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../settings/column_color_picker.dart';
import '../kanban/kanban_labels.dart';
import '../project/project_theme.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已创建标签「${result.name}」')),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(updated ? '标签已更新' : '标签不存在，无法更新')),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除标签「${label.name}」')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BoardController>(
      builder: (context, controller, _) {
        final labels = controller.appSettings.customLabels;
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
          body: labels.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.label_outline,
                        size: 52,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      const Text('还没有自定义标签'),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => _create(context),
                        icon: const Icon(Icons.add),
                        label: const Text('新建标签'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: labels.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final label = labels[index];
                    return ListTile(
                      leading: CircleAvatar(backgroundColor: label.color),
                      title: Text(label.name),
                      subtitle: Text(
                        '#${label.colorValue.toRadixString(16).substring(2).toUpperCase()}',
                      ),
                      onTap: () => _update(context, label),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '改名或改色',
                            onPressed: () => _update(context, label),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: '删除标签',
                            onPressed: () => _delete(context, label),
                            icon: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          floatingActionButton: labels.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _create(context),
                  icon: const Icon(Icons.add),
                  label: const Text('新建标签'),
                ),
        );
      },
    );
  }
}
