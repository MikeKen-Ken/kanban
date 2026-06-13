import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import 'trash_models.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  String _formatDeletedAt(int deletedAt) {
    final date = DateTime.fromMillisecondsSinceEpoch(deletedAt);
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  IconData _iconForType(TrashItemType type) => switch (type) {
        TrashItemType.card => Icons.sticky_note_2_outlined,
        TrashItemType.column => Icons.view_column_outlined,
        TrashItemType.project => Icons.folder_outlined,
        TrashItemType.customLabel => Icons.label_outline,
      };

  String _subtitleForItem(TrashItem item) {
    final parts = <String>[item.type.label];
    if (item.projectTitle != null && item.type != TrashItemType.project) {
      parts.add(item.projectTitle!);
    }
    if (item.columnTitle != null && item.type == TrashItemType.card) {
      parts.add(item.columnTitle!);
    }
    parts.add(_formatDeletedAt(item.deletedAt));
    return parts.join(' · ');
  }

  Future<void> _confirmRestore(
    BuildContext context,
    BoardController controller,
    TrashItem item,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('还原？'),
        content: Text('将还原「${item.displayName}」'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('还原'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final error = await controller.restoreTrashItem(item.id);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已还原「${item.displayName}」')),
      );
    }
  }

  Future<void> _confirmPermanentDelete(
    BuildContext context,
    BoardController controller,
    TrashItem item,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('永久删除？'),
        content: Text('「${item.displayName}」将被永久删除，无法恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await controller.permanentlyDeleteTrashItem(item.id);
  }

  Future<void> _confirmEmptyTrash(
    BuildContext context,
    BoardController controller,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站？'),
        content: const Text('所有项目将被永久删除，无法恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await controller.emptyTrash();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BoardController>(
      builder: (context, controller, _) {
        final items = controller.allTrashItems;
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            title: const Text('回收站'),
            actions: [
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmEmptyTrash(context, controller),
                  child: Text(
                    '清空',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
          body: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '回收站为空',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '删除的卡片、列、项目会出现在这里',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: Icon(_iconForType(item.type)),
                      title: Text(item.displayName),
                      subtitle: Text(_subtitleForItem(item)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '还原',
                            icon: const Icon(Icons.restore),
                            onPressed: () =>
                                _confirmRestore(context, controller, item),
                          ),
                          IconButton(
                            tooltip: '永久删除',
                            icon: Icon(
                              Icons.delete_forever_outlined,
                              color: theme.colorScheme.error,
                            ),
                            onPressed: () => _confirmPermanentDelete(
                              context,
                              controller,
                              item,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
