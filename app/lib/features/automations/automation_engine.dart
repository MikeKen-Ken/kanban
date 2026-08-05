import '../../features/kanban/kanban_labels.dart';
import '../../models/kanban_models.dart';
import 'automation_models.dart';

/// 自动化引擎对单张卡片建议的变更（纯计算，不写盘）。
class AutomationEffect {
  const AutomationEffect({
    required this.ruleId,
    required this.ruleName,
    this.completed,
    this.moveToDone = false,
    this.priority,
    this.addLabelKey,
    this.clearReminder = false,
  });

  final String ruleId;
  final String ruleName;
  final bool? completed;
  final bool moveToDone;
  final CardPriority? priority;
  final String? addLabelKey;
  final bool clearReminder;
}

/// 根据触发事件计算应执行的自动化效果。
class AutomationEngine {
  const AutomationEngine();

  List<AutomationEffect> effectsForMove({
    required List<AutomationRule> rules,
    required String toColumnId,
    required KanbanCard card,
  }) {
    return _collect(
      rules: rules,
      matches: (rule) =>
          rule.trigger == AutomationTrigger.movedToColumn &&
          rule.triggerColumnId == toColumnId,
      card: card,
    );
  }

  List<AutomationEffect> effectsForCompleted({
    required List<AutomationRule> rules,
    required KanbanCard card,
  }) {
    return _collect(
      rules: rules,
      matches: (rule) => rule.trigger == AutomationTrigger.completed,
      card: card,
    );
  }

  List<AutomationEffect> effectsForChecklistAllDone({
    required List<AutomationRule> rules,
    required KanbanCard card,
  }) {
    if (card.checklist.isEmpty ||
        card.checklist.any((item) => !item.completed)) {
      return const [];
    }
    return _collect(
      rules: rules,
      matches: (rule) => rule.trigger == AutomationTrigger.checklistAllDone,
      card: card,
    );
  }

  List<AutomationEffect> effectsForOverdue({
    required List<AutomationRule> rules,
    required KanbanCard card,
    required DateTime now,
  }) {
    final due = card.dueDate;
    if (card.completed || due == null) return const [];
    final dueDay = DateTime.fromMillisecondsSinceEpoch(due);
    final today = DateTime(now.year, now.month, now.day);
    if (!dueDay.isBefore(today)) return const [];
    return _collect(
      rules: rules,
      matches: (rule) => rule.trigger == AutomationTrigger.overdue,
      card: card,
    );
  }

  List<AutomationEffect> _collect({
    required List<AutomationRule> rules,
    required bool Function(AutomationRule rule) matches,
    required KanbanCard card,
  }) {
    final effects = <AutomationEffect>[];
    for (final rule in rules) {
      if (!rule.enabled || !matches(rule)) continue;
      final effect = _effectFor(rule, card);
      if (effect != null) effects.add(effect);
    }
    return effects;
  }

  AutomationEffect? _effectFor(AutomationRule rule, KanbanCard card) {
    switch (rule.action) {
      case AutomationActionType.markCompleted:
        if (card.completed) return null;
        return AutomationEffect(
          ruleId: rule.id,
          ruleName: rule.name,
          completed: true,
        );
      case AutomationActionType.moveToDoneColumn:
        return AutomationEffect(
          ruleId: rule.id,
          ruleName: rule.name,
          completed: true,
          moveToDone: true,
        );
      case AutomationActionType.setPriority:
        final priority = CardPriority.fromString(rule.actionPriority);
        if (card.priority == priority) return null;
        return AutomationEffect(
          ruleId: rule.id,
          ruleName: rule.name,
          priority: priority,
        );
      case AutomationActionType.addLabel:
        final key = rule.actionLabelKey.trim();
        if (key.isEmpty || card.labels.contains(key)) return null;
        return AutomationEffect(
          ruleId: rule.id,
          ruleName: rule.name,
          addLabelKey: key,
        );
      case AutomationActionType.clearReminder:
        if (card.reminderAt == null) return null;
        return AutomationEffect(
          ruleId: rule.id,
          ruleName: rule.name,
          clearReminder: true,
        );
    }
  }
}
