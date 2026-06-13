import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/board_controller.dart';
import '../features/kanban/kanban_column_list.dart';
import '../models/kanban_models.dart';
import '../settings/column_color_picker.dart';

class KanbanColumnWidget extends StatelessWidget {
  const KanbanColumnWidget({
    super.key,
    required this.column,
    this.searchQuery = '',
  });

  final KanbanColumn column;
  final String searchQuery;

  List<KanbanCard> get _sortedCards {
    final cards = [...column.cards]..sort((a, b) => a.order.compareTo(b.order));
    return cards;
  }

  Future<void> _addCard(BuildContext context) async {
    final controller = context.read<BoardController>();
    final titleController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('在「${column.title}」添加卡片'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '标题',
            hintText: '输入后回车快速添加',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );

    // note: 点击遮罩或返回键时 result 为 null；有内容时视为添加，仅「取消」为放弃
    final title = titleController.text.trim();
    if (title.isNotEmpty && result != false) {
      await controller.addCard(column.id, title);
    }
  }

  Future<void> _renameColumn(BuildContext context) async {
    final controller = context.read<BoardController>();
    final textController = TextEditingController(text: column.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名列'),
        content: TextField(
          controller: textController,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) {
      await controller.renameColumn(column.id, title);
    }
  }

  Future<void> _confirmDeleteColumn(BuildContext context) async {
    final controller = context.read<BoardController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除列？'),
        content: Text('将删除「${column.title}」及其全部卡片'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteColumn(column.id);
    }
  }

  Future<void> _pickColumnColor(BuildContext context) async {
    final controller = context.read<BoardController>();
    final picked = await showColumnColorPicker(
      context: context,
      currentColorValue: column.colorValue,
    );
    if (picked == column.colorValue) return;
    await controller.updateColumnColor(column.id, picked);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final columnColor =
        column.colorValue != null ? Color(column.colorValue!) : null;
    final cards = _sortedCards;
    final allColumns =
        context.watch<BoardController>().board?.columns ?? [];
    final visibleCount =
        cards.where((c) => c.matchesSearch(searchQuery)).length;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: columnColor != null
            ? columnColor.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: columnColor ?? colorScheme.outlineVariant,
          width: columnColor != null ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (columnColor != null) ...[
                        Container(
                          width: 4,
                          height: 20,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: columnColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          column.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: columnColor,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    searchQuery.isEmpty
                        ? '${cards.length}'
                        : '$visibleCount/${cards.length}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'color':
                        _pickColumnColor(context);
                      case 'rename':
                        _renameColumn(context);
                      case 'delete':
                        _confirmDeleteColumn(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'color', child: Text('设置颜色')),
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除列')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: KanbanColumnList(
              columnId: column.id,
              cards: cards,
              allColumns: allColumns,
              searchQuery: searchQuery,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: OutlinedButton.icon(
              onPressed: () => _addCard(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加卡片'),
            ),
          ),
        ],
      ),
    );
  }
}
