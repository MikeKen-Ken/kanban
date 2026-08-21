import 'package:flutter/material.dart';

import 'filter_spec.dart';

Future<FilterSpec?> showCardFilterSheet({
  required BuildContext context,
  required FilterSpec initial,
  required Map<String, String> labels,
  Map<String, String> projects = const {},
  bool showSort = false,
}) {
  return showModalBottomSheet<FilterSpec>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FilterSheet(
      initial: initial,
      labels: labels,
      projects: projects,
      showSort: showSort,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.labels,
    required this.projects,
    required this.showSort,
  });

  final FilterSpec initial;
  final Map<String, String> labels;
  final Map<String, String> projects;
  final bool showSort;

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

  void _toggleProject(String id) {
    final next = [..._value.projectIds];
    next.contains(id) ? next.remove(id) : next.add(id);
    setState(() => _value = _value.copyWith(projectIds: next));
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
                  Text('Filter cards',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        setState(() => _value = const FilterSpec()),
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.projects.isNotEmpty) ...[
                Text('Projects', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in widget.projects.entries)
                      FilterChip(
                        label: Text(entry.value),
                        selected: _value.projectIds.contains(entry.key),
                        onSelected: (_) => _toggleProject(entry.key),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              Text('Date', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<DueDateFilter>(
                segments: const [
                  ButtonSegment(value: DueDateFilter.any, label: Text('Any')),
                  ButtonSegment(
                      value: DueDateFilter.today, label: Text('Today')),
                  ButtonSegment(
                      value: DueDateFilter.overdue, label: Text('Overdue')),
                  ButtonSegment(
                      value: DueDateFilter.thisWeek, label: Text('This week')),
                ],
                selected: {_value.dueDate},
                onSelectionChanged: (value) => setState(
                  () => _value = _value.copyWith(dueDate: value.single),
                ),
              ),
              const SizedBox(height: 20),
              Text('Status', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<CompletionFilter>(
                segments: const [
                  ButtonSegment(
                      value: CompletionFilter.any, label: Text('Any')),
                  ButtonSegment(
                      value: CompletionFilter.incomplete,
                      label: Text('Incomplete')),
                  ButtonSegment(
                      value: CompletionFilter.completed,
                      label: Text('Completed')),
                ],
                selected: {_value.completion},
                onSelectionChanged: (value) => setState(
                  () => _value = _value.copyWith(completion: value.single),
                ),
              ),
              const SizedBox(height: 20),
              Text('Priority', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final item in const [
                    ('high', 'High'),
                    ('medium', 'Medium'),
                    ('low', 'Low'),
                    ('none', 'None'),
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
                    Text('Labels',
                        style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    DropdownButton<LabelMatchMode>(
                      value: _value.labelMatchMode,
                      items: const [
                        DropdownMenuItem(
                          value: LabelMatchMode.any,
                          child: Text('Any selected'),
                        ),
                        DropdownMenuItem(
                          value: LabelMatchMode.all,
                          child: Text('All selected'),
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
              if (widget.showSort) ...[
                const SizedBox(height: 20),
                Text('Sort', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<CardSortField>(
                        initialValue: _value.sortField,
                        decoration:
                            const InputDecoration(labelText: 'Sort field'),
                        items: [
                          for (final item in const [
                            (CardSortField.dueDate, '到期日'),
                            (CardSortField.priority, '优先级'),
                            (CardSortField.title, '标题'),
                            (CardSortField.createdAt, '创建时间'),
                            (CardSortField.updatedAt, '更新时间'),
                            (CardSortField.project, '项目'),
                            (CardSortField.column, '列'),
                          ])
                            DropdownMenuItem(
                              value: item.$1,
                              child: Text(item.$2),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(
                              () => _value = _value.copyWith(sortField: value),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<SortDirection>(
                        initialValue: _value.sortDirection,
                        decoration: const InputDecoration(labelText: '方向'),
                        items: const [
                          DropdownMenuItem(
                            value: SortDirection.ascending,
                            child: Text('升序'),
                          ),
                          DropdownMenuItem(
                            value: SortDirection.descending,
                            child: Text('降序'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(
                              () => _value =
                                  _value.copyWith(sortDirection: value),
                            );
                          }
                        },
                      ),
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
