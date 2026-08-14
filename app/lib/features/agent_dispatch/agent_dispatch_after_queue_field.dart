import 'package:flutter/material.dart';

import 'agent_dispatch_after_queue.dart';

class AgentDispatchAfterQueueField extends StatelessWidget {
  const AgentDispatchAfterQueueField({
    required this.steps,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final List<AgentDispatchAfterStep> steps;
  final bool enabled;
  final ValueChanged<List<AgentDispatchAfterStep>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('完成后队列', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          '全部卡片处理完后按顺序执行。上传会等到真正结束后才进入下一步；休眠/关机只立即执行一次，不会在下次开机自动重复。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final step in AgentDispatchAfterStep.values)
              ActionChip(
                label: Text('添加${step.label}'),
                onPressed: !enabled || steps.contains(step)
                    ? null
                    : () => onChanged(addAfterQueueStep(steps, step)),
              ),
          ],
        ),
        if (steps.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('未添加动作', style: theme.textTheme.bodySmall),
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
                  tooltip: '移除',
                  onPressed: enabled
                      ? () =>
                          onChanged(removeAfterQueueStepAt(steps, index))
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
