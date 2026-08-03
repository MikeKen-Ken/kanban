enum ActivityAction {
  created,
  updated,
  moved,
  completed,
  reopened,
  deleted,
  restored,
  dueDateChanged;

  String get label => switch (this) {
        ActivityAction.created => '已创建',
        ActivityAction.updated => '已更新',
        ActivityAction.moved => '已移动',
        ActivityAction.completed => '已完成',
        ActivityAction.reopened => '已重新打开',
        ActivityAction.deleted => '已删除',
        ActivityAction.restored => '已还原',
        ActivityAction.dueDateChanged => '已调整日期',
      };

  static ActivityAction fromString(String? value) {
    return ActivityAction.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ActivityAction.updated,
    );
  }
}

/// 项目内不可变的追加型活动事件。
class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.projectId,
    required this.entityType,
    required this.entityId,
    required this.entityTitle,
    required this.action,
    required this.occurredAt,
    this.details = const {},
  });

  final String id;
  final String projectId;
  final String entityType;
  final String entityId;
  final String entityTitle;
  final ActivityAction action;
  final int occurredAt;
  final Map<String, String> details;

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'entityType': entityType,
        'entityId': entityId,
        'entityTitle': entityTitle,
        'action': action.name,
        'occurredAt': occurredAt,
        if (details.isNotEmpty) 'details': details,
      };

  factory ActivityEvent.fromJson(Map<String, dynamic> json) {
    final details = json['details'] as Map<String, dynamic>?;
    return ActivityEvent(
      id: json['id'] as String,
      projectId: json['projectId'] as String? ?? '',
      entityType: json['entityType'] as String? ?? 'card',
      entityId: json['entityId'] as String? ?? '',
      entityTitle: json['entityTitle'] as String? ?? '',
      action: ActivityAction.fromString(json['action'] as String?),
      occurredAt: json['occurredAt'] as int? ?? 0,
      details: details == null
          ? const {}
          : details.map((key, value) => MapEntry(key, value.toString())),
    );
  }
}

class ActivityLog {
  const ActivityLog({this.events = const []});

  static const maxEvents = 1000;

  final List<ActivityEvent> events;

  ActivityLog mergeWith(ActivityLog other) {
    final byId = <String, ActivityEvent>{
      for (final event in events) event.id: event,
      for (final event in other.events) event.id: event,
    };
    final merged = byId.values.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return ActivityLog(
      events: merged.take(maxEvents).toList(growable: false),
    );
  }

  ActivityLog add(ActivityEvent event) {
    return ActivityLog(events: [event, ...events])
        .mergeWith(const ActivityLog());
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'events': events.map((event) => event.toJson()).toList(),
      };

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    return ActivityLog(
      events: (json['events'] as List<dynamic>? ?? [])
          .map((value) => ActivityEvent.fromJson(value as Map<String, dynamic>))
          .toList(),
    ).mergeWith(const ActivityLog());
  }
}
