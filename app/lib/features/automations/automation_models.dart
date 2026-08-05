/// 自动化触发条件。
enum AutomationTrigger {
  /// 卡片移入指定列
  movedToColumn,

  /// 卡片被标记为完成
  completed,

  /// 清单全部勾选完成
  checklistAllDone,

  /// 到期日已过且仍未完成（由调度检查触发）
  overdue,
}

extension AutomationTriggerX on AutomationTrigger {
  String get label => switch (this) {
        AutomationTrigger.movedToColumn => '移入指定列',
        AutomationTrigger.completed => '标记完成',
        AutomationTrigger.checklistAllDone => '清单全部完成',
        AutomationTrigger.overdue => '已逾期',
      };

  static AutomationTrigger fromString(String? value) {
    return AutomationTrigger.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AutomationTrigger.movedToColumn,
    );
  }
}

/// 自动化动作。
enum AutomationActionType {
  markCompleted,
  moveToDoneColumn,
  setPriority,
  addLabel,
  clearReminder,
}

extension AutomationActionTypeX on AutomationActionType {
  String get label => switch (this) {
        AutomationActionType.markCompleted => '标记完成',
        AutomationActionType.moveToDoneColumn => '移到已完成列',
        AutomationActionType.setPriority => '设置优先级',
        AutomationActionType.addLabel => '添加标签',
        AutomationActionType.clearReminder => '清除提醒',
      };

  static AutomationActionType fromString(String? value) {
    return AutomationActionType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AutomationActionType.markCompleted,
    );
  }
}

/// 单条自动化规则（随项目设置同步）。
class AutomationRule {
  const AutomationRule({
    required this.id,
    required this.name,
    this.enabled = true,
    this.trigger = AutomationTrigger.movedToColumn,
    this.triggerColumnId = '',
    this.action = AutomationActionType.moveToDoneColumn,
    this.actionPriority = 'high',
    this.actionLabelKey = '',
  });

  final String id;
  final String name;
  final bool enabled;
  final AutomationTrigger trigger;

  /// [AutomationTrigger.movedToColumn] 时的目标列 id
  final String triggerColumnId;
  final AutomationActionType action;

  /// [AutomationActionType.setPriority] 时的优先级名
  final String actionPriority;

  /// [AutomationActionType.addLabel] 时的标签 key
  final String actionLabelKey;

  AutomationRule copyWith({
    String? id,
    String? name,
    bool? enabled,
    AutomationTrigger? trigger,
    String? triggerColumnId,
    AutomationActionType? action,
    String? actionPriority,
    String? actionLabelKey,
  }) {
    return AutomationRule(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      trigger: trigger ?? this.trigger,
      triggerColumnId: triggerColumnId ?? this.triggerColumnId,
      action: action ?? this.action,
      actionPriority: actionPriority ?? this.actionPriority,
      actionLabelKey: actionLabelKey ?? this.actionLabelKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'trigger': trigger.name,
        if (triggerColumnId.isNotEmpty) 'triggerColumnId': triggerColumnId,
        'action': action.name,
        if (actionPriority.isNotEmpty) 'actionPriority': actionPriority,
        if (actionLabelKey.isNotEmpty) 'actionLabelKey': actionLabelKey,
      };

  factory AutomationRule.fromJson(Map<String, dynamic> json) {
    return AutomationRule(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名规则',
      enabled: json['enabled'] as bool? ?? true,
      trigger: AutomationTriggerX.fromString(json['trigger'] as String?),
      triggerColumnId: json['triggerColumnId'] as String? ?? '',
      action: AutomationActionTypeX.fromString(json['action'] as String?),
      actionPriority: json['actionPriority'] as String? ?? 'high',
      actionLabelKey: json['actionLabelKey'] as String? ?? '',
    );
  }

  static bool listEquals(List<AutomationRule> a, List<AutomationRule> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].name != b[i].name ||
          a[i].enabled != b[i].enabled ||
          a[i].trigger != b[i].trigger ||
          a[i].triggerColumnId != b[i].triggerColumnId ||
          a[i].action != b[i].action ||
          a[i].actionPriority != b[i].actionPriority ||
          a[i].actionLabelKey != b[i].actionLabelKey) {
        return false;
      }
    }
    return true;
  }
}
