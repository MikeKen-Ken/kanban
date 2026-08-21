import 'package:flutter/material.dart';

import '../../models/kanban_models.dart';
import 'agent_interaction.dart';

/// 对话底部的追问管理区：勾选多删、点按编辑。
class CardAgentFollowUpPanel extends StatelessWidget {
  const CardAgentFollowUpPanel({
    required this.items,
    required this.selectedIds,
    required this.enabled,
    required this.onToggleSelected,
    required this.onEdit,
    required this.onDeleteSelected,
    super.key,
  });

  final List<ChecklistItem> items;
  final Set<String> selectedIds;
  final bool enabled;
  final ValueChanged<String> onToggleSelected;
  final ValueChanged<String> onEdit;
  final VoidCallback onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Text('Manage follow-ups', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton(
              key: const ValueKey('card-agent-follow-up-delete-selected'),
              onPressed: !enabled || selectedIds.isEmpty
                  ? null
                  : onDeleteSelected,
              child: Text(
                selectedIds.isEmpty
                    ? 'Delete selected'
                    : 'Delete selected (${selectedIds.length})',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Check items to delete; tap text to edit.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final body = agentFollowUpFeedbackBody(item.text) ?? item.text;
              final selected = selectedIds.contains(item.id);
              return CheckboxListTile(
                key: ValueKey('card-agent-follow-up-${item.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: selected,
                onChanged: !enabled
                    ? null
                    : (_) => onToggleSelected(item.id),
                title: InkWell(
                  onTap: !enabled ? null : () => onEdit(item.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(body),
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 从验证反馈中筛出 Agent 追问项（保持原顺序）。
List<ChecklistItem> agentFollowUpFeedbackItems(
  Iterable<ChecklistItem> feedback,
) {
  return [
    for (final item in feedback)
      if (agentFollowUpFeedbackBody(item.text) != null) item,
  ];
}
