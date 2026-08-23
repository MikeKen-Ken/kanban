import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../common/app_snack_bar.dart';
import '../kanban/kanban_labels.dart';
import 'label_editor_dialog.dart';

class LabelManagementScreen extends StatelessWidget {
  const LabelManagementScreen({super.key});

  Future<void> _update(BuildContext context, KanbanLabel label) async {
    final result = await showLabelFormDialog(context, label: label);
    if (result == null || !context.mounted) return;
    final updated = await context.read<BoardController>().updateCustomLabel(
          label.key,
          name: result.name,
          colorValue: result.colorValue,
        );
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: updated ? 'Label updated' : 'Label no longer exists',
    );
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
            title: const Text('Labels'),
            actions: [
              IconButton(
                tooltip: 'Manage labels',
                onPressed: () => showLabelEditorDialog(context),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            children: [
              Text('Built-in labels', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Built-in labels cannot be edited or deleted',
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
              Text('Custom labels', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              if (customLabels.isEmpty)
                Text(
                  'No custom labels yet',
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
            onPressed: () => showLabelEditorDialog(context),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Manage labels'),
          ),
        );
      },
    );
  }
}
