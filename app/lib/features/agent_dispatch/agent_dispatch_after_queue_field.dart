import 'package:flutter/material.dart';

import 'agent_dispatch_after_queue.dart';
import 'agent_dispatch_section_header.dart';

class AgentDispatchAfterQueueField extends StatelessWidget {
  const AgentDispatchAfterQueueField({
    required this.steps,
    required this.enabled,
    required this.onChanged,
    this.description = 'These actions run after the batch finishes.',
    this.runOnFailure = true,
    this.onRunOnFailureChanged,
    super.key,
  });

  final List<AgentDispatchAfterStep> steps;
  final bool enabled;
  final ValueChanged<List<AgentDispatchAfterStep>> onChanged;
  final String description;
  final bool runOnFailure;
  final ValueChanged<bool>? onRunOnFailureChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AgentDispatchSectionHeader(
          title: 'Completion queue',
          tone: AgentDispatchSectionTone.queue,
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: enabled && onRunOnFailureChanged != null
              ? () => onRunOnFailureChanged!(!runOnFailure)
              : null,
          child: Row(
            children: [
              Checkbox(
                value: runOnFailure,
                onChanged: enabled && onRunOnFailureChanged != null
                    ? (value) => onRunOnFailureChanged!(value ?? false)
                    : null,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  'Continue after failure',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final step in AgentDispatchAfterStep.values)
              ActionChip(
                tooltip: step.description,
                label: Text(step.label),
                onPressed: !enabled || steps.contains(step)
                    ? null
                    : () => onChanged(addAfterQueueStep(steps, step)),
              ),
          ],
        ),
        if (steps.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('No actions added', style: theme.textTheme.bodySmall),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: steps.length,
            onReorder: enabled
                ? (oldIndex, newIndex) => onChanged(
                      reorderAfterQueueStep(steps, oldIndex, newIndex),
                    )
                : (_, __) {},
            itemBuilder: (context, index) {
              final step = steps[index];
              return ListTile(
                key: ValueKey('after-queue-$index-${step.name}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: enabled
                    ? ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      )
                    : const Icon(Icons.drag_handle),
                title: Text('${index + 1}. ${step.label}'),
                trailing: IconButton(
                  tooltip: 'Remove',
                  onPressed: enabled
                      ? () => onChanged(removeAfterQueueStepAt(steps, index))
                      : null,
                  icon: const Icon(Icons.close),
                ),
              );
            },
          ),
      ],
    );
  }
}
