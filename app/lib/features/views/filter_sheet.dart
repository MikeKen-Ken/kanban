import 'package:flutter/material.dart';

import 'filter_spec.dart';

Future<FilterSpec?> showCardFilterSheet({
  required BuildContext context,
  required FilterSpec initial,
  required Map<String, String> labels,
}) {
  return showModalBottomSheet<FilterSpec>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FilterSheet(initial: initial, labels: labels),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.labels});

  final FilterSpec initial;
  final Map<String, String> labels;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late FilterSpec _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  void _togglePriority(String priority) {
    final next = [..._value.priorities];
    next.contains(priority) ? next.remove(priority) : next.add(priority);
    setState(() => _value = _value.copyWith(priorities: next));
  }

  void _toggleLabel(String id) {
    final next = [..._value.labelIds];
    next.contains(id) ? next.remove(id) : next.add(id);
    setState(() => _value = _value.copyWith(labelIds: next));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('筛选卡片', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        setState(() => _value = const FilterSpec()),
                    child: const Text('重置'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('日期', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<DueDateFilter>(
                segments: const [
                  ButtonSegment(value: DueDateFilter.any, label: Text('全部')),
                  ButtonSegment(value: DueDateFilter.today, label: Text('今天')),
                  ButtonSegment(
                      value: DueDateFilter.overdue, label: Text('逾期')),
                  ButtonSegment(
                      value: DueDateFilter.thisWeek, label: Text('本周')),
                ],
                selected: {_value.dueDate},
                onSelectionChanged: (value) => setState(
                  () => _value = _value.copyWith(dueDate: value.single),
                ),
              ),
              const SizedBox(height: 20),
              Text('状态', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<CompletionFilter>(
                segments: const [
                  ButtonSegment(value: CompletionFilter.any, label: Text('全部')),
                  ButtonSegment(
                      value: CompletionFilter.incomplete, label: Text('未完成')),
                  ButtonSegment(
                      value: CompletionFilter.completed, label: Text('已完成')),
                ],
                selected: {_value.completion},
                onSelectionChanged: (value) => setState(
                  () => _value = _value.copyWith(completion: value.single),
                ),
              ),
              const SizedBox(height: 20),
              Text('优先级', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final item in const [
                    ('high', '高'),
                    ('medium', '中'),
                    ('low', '低'),
                    ('none', '无'),
                  ])
                    FilterChip(
                      label: Text(item.$2),
                      selected: _value.priorities.contains(item.$1),
                      onSelected: (_) => _togglePriority(item.$1),
                    ),
                ],
              ),
              if (widget.labels.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text('标签', style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    DropdownButton<LabelMatchMode>(
                      value: _value.labelMatchMode,
                      items: const [
                        DropdownMenuItem(
                          value: LabelMatchMode.any,
                          child: Text('满足任一'),
                        ),
                        DropdownMenuItem(
                          value: LabelMatchMode.all,
                          child: Text('满足全部'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(
                            () =>
                                _value = _value.copyWith(labelMatchMode: value),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in widget.labels.entries)
                      FilterChip(
                        label: Text(entry.value),
                        selected: _value.labelIds.contains(entry.key),
                        onSelected: (_) => _toggleLabel(entry.key),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _value),
                  child: const Text('应用筛选'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
