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
        ActivityAction.created => 'Created',
        ActivityAction.updated => 'Updated',
        ActivityAction.moved => 'Moved',
        ActivityAction.completed => 'Completed',
        ActivityAction.reopened => 'Reopened',
        ActivityAction.deleted => 'Deleted',
        ActivityAction.restored => 'Restored',
        ActivityAction.dueDateChanged => 'Due date changed',
      };

  static ActivityAction fromString(String? value) {
    return ActivityAction.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ActivityAction.updated,
    );
  }
}

/// 活动来源：用于区分本机操作、MCP 与自动化。
enum ActivitySource {
  user,
  mcp,
  automation;

  String get label => switch (this) {
        ActivitySource.user => 'Local',
        ActivitySource.mcp => 'MCP',
        ActivitySource.automation => 'Automation',
      };

  /// 活动列表副文案：提示如何恢复。
  String get recoveryHint => switch (this) {
        ActivitySource.user => '',
        ActivitySource.mcp =>
          'Can be undone from the toolbar or Trash, depending on the action',
        ActivitySource.automation =>
          'Triggered by a rule; use Undo to revert the latest local/MCP action',
      };

  static ActivitySource fromString(String? value) {
    return ActivitySource.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ActivitySource.user,
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
    this.source = ActivitySource.user,
    this.details = const {},
  });

  final String id;
  final String projectId;
  final String entityType;
  final String entityId;
  final String entityTitle;
  final ActivityAction action;
  final int occurredAt;
  final ActivitySource source;
  final Map<String, String> details;

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'entityType': entityType,
        'entityId': entityId,
        'entityTitle': entityTitle,
        'action': action.name,
        'occurredAt': occurredAt,
        if (source != ActivitySource.user) 'source': source.name,
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
      source: ActivitySource.fromString(json['source'] as String?),
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
    };
    for (final event in other.events) {
      byId[event.id] = event;
    }
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
