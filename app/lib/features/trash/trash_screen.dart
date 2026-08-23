import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import 'trash_models.dart';
import 'trash_auto_clear.dart';
import '../../common/app_snack_bar.dart';

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
        title: const Text('Restore?'),
        content: Text('Restore "${item.displayName}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final error = await controller.restoreTrashItem(item.id);
    if (!context.mounted) return;
    if (error != null) {
      showAppSnackBar(context, message: error);
    } else {
      showAppSnackBar(context, message: 'Restored "${item.displayName}"');
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
        title: const Text('Delete permanently?'),
        content: Text(
            '"${item.displayName}" will be permanently deleted and cannot be restored'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await controller.permanentlyDeleteTrashItem(item.id);
    if (!context.mounted) return;
    showAppSnackBar(context,
        message: 'Permanently deleted "${item.displayName}"');
  }

  Future<void> _confirmEmptyTrash(
    BuildContext context,
    BoardController controller,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Trash?'),
        content: const Text(
            'All Trash items will be permanently deleted and cannot be restored'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Empty'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await controller.emptyTrash();
    if (!context.mounted) return;
    showAppSnackBar(context, message: 'Trash emptied');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BoardController>(
      builder: (context, controller, _) {
        final items = controller.allTrashItems;
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Trash'),
            actions: [
              Selector<BoardController, int>(
                selector: (_, c) => c.appSettings.trashRetentionDays,
                builder: (context, days, _) {
                  final options = [
                    ...trashRetentionDayOptions,
                    if (!trashRetentionDayOptions.contains(days)) days,
                  ]..sort();
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: days,
                        items: [
                          for (final option in options)
                            DropdownMenuItem(
                              value: option,
                              child: Text(trashRetentionDaysLabel(option)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          controller.saveAppSettings(
                            controller.appSettings.copyWith(
                              trashRetentionDays: value,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmEmptyTrash(context, controller),
                  child: Text(
                    'Empty',
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
                        'Trash is empty',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Deleted cards, columns, and projects appear here',
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
                            tooltip: 'Restore',
                            icon: const Icon(Icons.restore),
                            onPressed: () =>
                                _confirmRestore(context, controller, item),
                          ),
                          IconButton(
                            tooltip: 'Delete permanently',
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
