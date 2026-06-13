import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/board_controller.dart';
import '../models/kanban_models.dart';

class KanbanColumnWidget extends StatelessWidget {
  const KanbanColumnWidget({super.key, required this.column});

  final KanbanColumn column;

  Future<void> _addCard(BuildContext context) async {
    final controller = context.read<BoardController>();
    final titleController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('在「${column.title}」添加卡片'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: '备注（可选）'),
              maxLines: 3,
            ),
          ],
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

    if (result == true && titleController.text.trim().isNotEmpty) {
      await controller.addCard(
        column.id,
        titleController.text.trim(),
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
      );
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    column.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'rename':
                        _renameColumn(context);
                      case 'delete':
                        _confirmDeleteColumn(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除列')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: column.cards.length,
              itemBuilder: (context, index) {
                final card = column.cards[index];
                return _KanbanCardTile(
                  columnId: column.id,
                  card: card,
                  allColumns: context.watch<BoardController>().board?.columns ?? [],
                );
              },
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

class _KanbanCardTile extends StatelessWidget {
  const _KanbanCardTile({
    required this.columnId,
    required this.card,
    required this.allColumns,
  });

  final String columnId;
  final KanbanCard card;
  final List<KanbanColumn> allColumns;

  Future<void> _editCard(BuildContext context) async {
    final controller = context.read<BoardController>();
    final titleController = TextEditingController(text: card.title);
    final descController = TextEditingController(text: card.description ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑卡片'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: '备注'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await controller.updateCard(
        columnId,
        card.id,
        title: titleController.text.trim(),
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
      );
    }
  }

  Future<void> _moveCard(BuildContext context) async {
    final controller = context.read<BoardController>();
    final targets = allColumns.where((c) => c.id != columnId).toList();
    if (targets.isEmpty) return;

    final targetId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('移动到'),
        children: targets
            .map(
              (col) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, col.id),
                child: Text(col.title),
              ),
            )
            .toList(),
      ),
    );

    if (targetId != null) {
      final target = targets.firstWhere((c) => c.id == targetId);
      await controller.moveCard(
        cardId: card.id,
        fromColumnId: columnId,
        toColumnId: targetId,
        toIndex: target.cards.length,
      );
    }
  }

  Future<void> _deleteCard(BuildContext context) async {
    final controller = context.read<BoardController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除卡片？'),
        content: Text(card.title),
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
      await controller.deleteCard(columnId, card.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(card.title),
        subtitle: card.description == null || card.description!.isEmpty
            ? null
            : Text(
                card.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        onTap: () => _editCard(context),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'move':
                _moveCard(context);
              case 'delete':
                _deleteCard(context);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'move', child: Text('移动')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }
}
