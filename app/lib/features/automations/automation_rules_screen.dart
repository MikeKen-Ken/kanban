import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../controllers/board_controller.dart';
import '../kanban/kanban_labels.dart';
import 'automation_models.dart';

/// 当前项目的自动化规则管理页。
class AutomationRulesScreen extends StatefulWidget {
  const AutomationRulesScreen({super.key});

  @override
  State<AutomationRulesScreen> createState() => _AutomationRulesScreenState();
}

class _AutomationRulesScreenState extends State<AutomationRulesScreen> {
  late List<AutomationRule> _rules;

  @override
  void initState() {
    super.initState();
    _rules = [
      ...context.read<BoardController>().projectSettings.automationRules,
    ];
  }

  Future<void> _persist() async {
    final controller = context.read<BoardController>();
    await controller.saveProjectSettings(
      controller.projectSettings.copyWith(automationRules: _rules),
    );
  }

  Future<void> _editRule([AutomationRule? existing]) async {
    final controller = context.read<BoardController>();
    final columns = controller.board?.columns ?? const [];
    var draft = existing ??
        AutomationRule(
          id: const Uuid().v4(),
          name: 'New rule',
          triggerColumnId: columns.isNotEmpty ? columns.first.id : '',
        );
    final nameController = TextEditingController(text: draft.name);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Create rule' : 'Edit rule'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AutomationTrigger>(
                  value: draft.trigger,
                  decoration: const InputDecoration(labelText: 'Trigger'),
                  items: [
                    for (final trigger in AutomationTrigger.values)
                      DropdownMenuItem(
                        value: trigger,
                        child: Text(trigger.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(
                        () => draft = draft.copyWith(trigger: value));
                  },
                ),
                if (draft.trigger == AutomationTrigger.movedToColumn) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: draft.triggerColumnId.isEmpty && columns.isNotEmpty
                        ? columns.first.id
                        : draft.triggerColumnId,
                    decoration:
                        const InputDecoration(labelText: 'Target column'),
                    items: [
                      for (final column in columns)
                        DropdownMenuItem(
                          value: column.id,
                          child: Text(column.title),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(
                        () => draft = draft.copyWith(triggerColumnId: value),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<AutomationActionType>(
                  value: draft.action,
                  decoration: const InputDecoration(labelText: 'Action'),
                  items: [
                    for (final action in AutomationActionType.values)
                      DropdownMenuItem(
                        value: action,
                        child: Text(action.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => draft = draft.copyWith(action: value));
                  },
                ),
                if (draft.action == AutomationActionType.setPriority) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: draft.actionPriority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: [
                      for (final priority in CardPriority.values)
                        DropdownMenuItem(
                          value: priority.name,
                          child: Text(priority.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(
                        () => draft = draft.copyWith(actionPriority: value),
                      );
                    },
                  ),
                ],
                if (draft.action == AutomationActionType.addLabel) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: draft.actionLabelKey.isEmpty
                        ? null
                        : draft.actionLabelKey,
                    decoration: const InputDecoration(labelText: 'Label'),
                    items: [
                      for (final label in labelsForEditing(
                        controller.appSettings.customLabels,
                        themeId: controller.projectSettings.themeId,
                        selectedKeys: [draft.actionLabelKey],
                      ))
                        DropdownMenuItem(
                          value: label.key,
                          child: Text(label.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(
                        () => draft = draft.copyWith(actionLabelKey: value),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final name = nameController.text.trim();
    nameController.dispose();
    if (saved != true || name.isEmpty || !mounted) return;
    draft = draft.copyWith(name: name);
    setState(() {
      final index = _rules.indexWhere((rule) => rule.id == draft.id);
      if (index >= 0) {
        _rules = [..._rules]..[index] = draft;
      } else {
        _rules = [..._rules, draft];
      }
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Automation rules')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editRule(),
        icon: const Icon(Icons.add),
        label: const Text('Create rule'),
      ),
      body: _rules.isEmpty
          ? const Center(child: Text('No automation rules yet'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _rules.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final rule = _rules[index];
                return SwitchListTile(
                  value: rule.enabled,
                  title: Text(rule.name),
                  subtitle: Text(
                    '${rule.trigger.label} → ${rule.action.label}',
                  ),
                  secondary: IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editRule(rule),
                  ),
                  onChanged: (enabled) async {
                    setState(() {
                      _rules = [..._rules]..[index] =
                          rule.copyWith(enabled: enabled);
                    });
                    await _persist();
                  },
                );
              },
            ),
    );
  }
}
