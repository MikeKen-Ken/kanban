/// 跨项目查询使用的轻量卡片引用。
///
/// [source] 可由调用方保存原始领域对象，不参与 JSON 序列化，也不影响查询。
class CardReference {
  const CardReference({
    required this.projectId,
    required this.columnId,
    required this.cardId,
    required this.title,
    this.projectName = '',
    this.columnName = '',
    this.description,
    this.labelIds = const [],
    this.labelNames = const [],
    this.checklistTexts = const [],
    this.priority = 'none',
    this.completed = false,
    this.dueDate,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.order = 0,
    this.blockedByIds = const [],
    this.relatedIds = const [],
    this.links = const [],
    this.source,
  });

  final String projectId;
  final String projectName;
  final String columnId;
  final String columnName;
  final String cardId;
  final String title;
  final String? description;
  final List<String> labelIds;
  final List<String> labelNames;
  final List<String> checklistTexts;
  final String priority;
  final bool completed;
  final int? dueDate;
  final int createdAt;
  final int updatedAt;
  final int order;
  final List<String> blockedByIds;
  final List<String> relatedIds;

  /// 外链摘要：`{id, url, title?}`
  final List<Map<String, dynamic>> links;
  final Object? source;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        if (projectName.isNotEmpty) 'projectName': projectName,
        'columnId': columnId,
        if (columnName.isNotEmpty) 'columnName': columnName,
        'cardId': cardId,
        'title': title,
        if (description != null) 'description': description,
        if (labelIds.isNotEmpty) 'labelIds': labelIds,
        if (labelNames.isNotEmpty) 'labelNames': labelNames,
        if (checklistTexts.isNotEmpty) 'checklistTexts': checklistTexts,
        if (priority != 'none') 'priority': priority,
        if (completed) 'completed': true,
        if (dueDate != null) 'dueDate': dueDate,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'order': order,
        if (blockedByIds.isNotEmpty) 'blockedByIds': blockedByIds,
        if (relatedIds.isNotEmpty) 'relatedIds': relatedIds,
        if (links.isNotEmpty) 'links': links,
      };

  factory CardReference.fromJson(Map<String, dynamic> json) {
    return CardReference(
      projectId: _string(json['projectId']),
      projectName: _string(json['projectName'] ?? json['projectTitle']),
      columnId: _string(json['columnId']),
      columnName: _string(json['columnName'] ?? json['columnTitle']),
      cardId: _string(json['cardId'] ?? json['id']),
      title: _string(json['title']),
      description:
          json['description'] is String ? json['description'] as String : null,
      labelIds: _strings(json['labelIds'] ?? json['labels']),
      labelNames: _strings(json['labelNames']),
      checklistTexts: _strings(json['checklistTexts'] ?? json['checklist']),
      priority: _string(json['priority'], fallback: 'none'),
      completed: json['completed'] is bool ? json['completed'] as bool : false,
      dueDate: _nullableInt(json['dueDate']),
      createdAt: _int(json['createdAt']),
      updatedAt: _int(json['updatedAt'] ?? json['createdAt']),
      order: _int(json['order']),
      blockedByIds: _strings(json['blockedByIds']),
      relatedIds: _strings(json['relatedIds']),
      links: _linkMaps(json['links']),
    );
  }
}

String _string(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

List<String> _strings(Object? value) {
  if (value is String) return [value];
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}

int _int(Object? value) => value is num ? value.toInt() : 0;

int? _nullableInt(Object? value) => value is num ? value.toInt() : null;

List<Map<String, dynamic>> _linkMaps(Object? value) {
  if (value is! List) return const [];
  final links = <Map<String, dynamic>>[];
  for (final entry in value) {
    if (entry is! Map) continue;
    final map = Map<String, dynamic>.from(entry);
    final url = _string(map['url']);
    if (url.isEmpty) continue;
    links.add({
      'id': _string(map['id']),
      'url': url,
      if (_string(map['title']).isNotEmpty) 'title': _string(map['title']),
    });
  }
  return links;
}
