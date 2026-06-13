import 'dart:convert';

import '../features/kanban/kanban_labels.dart';

class KanbanBoard {
  KanbanBoard({
    required this.id,
    required this.title,
    required this.columns,
    required this.updatedAt,
    required this.revision,
  });

  final String id;
  final String title;
  final List<KanbanColumn> columns;
  final int updatedAt;
  final int revision;

  KanbanBoard copyWith({
    String? id,
    String? title,
    List<KanbanColumn>? columns,
    int? updatedAt,
    int? revision,
  }) {
    return KanbanBoard(
      id: id ?? this.id,
      title: title ?? this.title,
      columns: columns ?? this.columns,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'columns': columns.map((c) => c.toJson()).toList(),
        'updatedAt': updatedAt,
        'revision': revision,
      };

  /// 元数据 JSON（不含卡片），配合 columns/{id}.json 使用
  Map<String, dynamic> toMetadataJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt,
        'revision': revision,
        'version': 2,
        'columns': columns
            .map((c) => {'id': c.id, 'order': c.order})
            .toList(),
      };

  /// note: 旧版单文件格式，columns 内嵌完整卡片数据
  static bool isLegacyMonolithic(Map<String, dynamic> json) {
    if (json['version'] == 2) return false;
    final cols = json['columns'] as List<dynamic>?;
    if (cols == null || cols.isEmpty) return false;
    final first = cols.first as Map<String, dynamic>;
    return first.containsKey('cards');
  }

  factory KanbanBoard.fromJson(Map<String, dynamic> json) {
    return KanbanBoard(
      id: json['id'] as String,
      title: json['title'] as String? ?? '我的看板',
      updatedAt: json['updatedAt'] as int? ?? 0,
      revision: json['revision'] as int? ?? 0,
      columns: (json['columns'] as List<dynamic>? ?? [])
          .map((e) => KanbanColumn.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  factory KanbanBoard.fromMetadataJson(
    Map<String, dynamic> json,
    List<KanbanColumn> columns,
  ) {
    final sorted = [...columns]..sort((a, b) => a.order.compareTo(b.order));
    return KanbanBoard(
      id: json['id'] as String,
      title: json['title'] as String? ?? '我的看板',
      updatedAt: json['updatedAt'] as int? ?? 0,
      revision: json['revision'] as int? ?? 0,
      columns: sorted,
    );
  }

  static KanbanBoard empty({
    required String id,
    String title = '我的看板',
    String doneColumnTitle = '已完成',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return KanbanBoard(
      id: id,
      title: title,
      updatedAt: now,
      revision: 1,
      columns: [
        KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: [],
        ),
        KanbanColumn(
          id: 'doing',
          title: '进行中',
          order: 1,
          cards: [],
        ),
        KanbanColumn(
          id: 'done',
          title: doneColumnTitle,
          order: 2,
          cards: [],
        ),
      ],
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory KanbanBoard.fromJsonString(String source) {
    return KanbanBoard.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }

  /// note: 合并策略 — 修订号更高者优先；相同则时间戳更新者优先
  KanbanBoard mergeWith(KanbanBoard remote) {
    if (remote.revision > revision) return remote;
    if (remote.revision < revision) return this;
    return remote.updatedAt >= updatedAt ? remote : this;
  }
}

class KanbanColumn {
  KanbanColumn({
    required this.id,
    required this.title,
    required this.order,
    required this.cards,
    this.colorValue,
  });

  final String id;
  final String title;
  final int order;
  final List<KanbanCard> cards;

  /// 列主题色 ARGB；null 使用应用默认样式
  final int? colorValue;

  KanbanColumn copyWith({
    String? id,
    String? title,
    int? order,
    List<KanbanCard>? cards,
    Object? colorValue = _columnColorSentinel,
  }) {
    return KanbanColumn(
      id: id ?? this.id,
      title: title ?? this.title,
      order: order ?? this.order,
      cards: cards ?? this.cards,
      colorValue: colorValue == _columnColorSentinel
          ? this.colorValue
          : colorValue as int?,
    );
  }

  static const _columnColorSentinel = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'order': order,
        if (colorValue != null) 'color': colorValue,
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  factory KanbanColumn.fromJson(Map<String, dynamic> json) {
    return KanbanColumn(
      id: json['id'] as String,
      title: json['title'] as String,
      order: json['order'] as int? ?? 0,
      colorValue: json['color'] as int?,
      cards: (json['cards'] as List<dynamic>? ?? [])
          .map((e) => KanbanCard.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ChecklistItem {
  ChecklistItem({
    required this.id,
    required this.text,
    this.completed = false,
  });

  final String id;
  final String text;
  final bool completed;

  ChecklistItem copyWith({
    String? id,
    String? text,
    bool? completed,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'completed': completed,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] as String,
      text: json['text'] as String,
      completed: json['completed'] as bool? ?? false,
    );
  }
}

class KanbanCard {
  KanbanCard({
    required this.id,
    required this.title,
    this.description,
    required this.order,
    required this.createdAt,
    this.completed = false,
    this.completedAt,
    this.dueDate,
    this.priority = CardPriority.none,
    this.labels = const [],
    this.checklist = const [],
    this.colorValue,
  });

  final String id;
  final String title;
  final String? description;
  final int order;
  final int createdAt;
  final bool completed;
  final int? completedAt;
  final int? dueDate;
  final CardPriority priority;
  final List<String> labels;
  final List<ChecklistItem> checklist;

  /// 卡片背景色 ARGB；null 使用默认 Card 样式
  final int? colorValue;

  int get checklistDone =>
      checklist.where((item) => item.completed).length;

  bool get hasChecklist => checklist.isNotEmpty;

  KanbanCard copyWith({
    String? id,
    String? title,
    String? description,
    int? order,
    int? createdAt,
    bool? completed,
    Object? completedAt = _sentinel,
    Object? dueDate = _sentinel,
    CardPriority? priority,
    List<String>? labels,
    List<ChecklistItem>? checklist,
    Object? colorValue = _sentinel,
  }) {
    return KanbanCard(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      completed: completed ?? this.completed,
      completedAt: completedAt == _sentinel
          ? this.completedAt
          : completedAt as int?,
      dueDate: dueDate == _sentinel ? this.dueDate : dueDate as int?,
      priority: priority ?? this.priority,
      labels: labels ?? this.labels,
      checklist: checklist ?? this.checklist,
      colorValue:
          colorValue == _sentinel ? this.colorValue : colorValue as int?,
    );
  }

  static const _sentinel = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'order': order,
        'createdAt': createdAt,
        'completed': completed,
        if (completedAt != null) 'completedAt': completedAt,
        if (dueDate != null) 'dueDate': dueDate,
        if (priority != CardPriority.none) 'priority': priority.name,
        if (labels.isNotEmpty) 'labels': labels,
        if (checklist.isNotEmpty)
          'checklist': checklist.map((c) => c.toJson()).toList(),
        if (colorValue != null) 'color': colorValue,
      };

  factory KanbanCard.fromJson(Map<String, dynamic> json) {
    return KanbanCard(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      order: json['order'] as int? ?? 0,
      createdAt: json['createdAt'] as int? ?? 0,
      completed: json['completed'] as bool? ?? false,
      completedAt: json['completedAt'] as int?,
      dueDate: json['dueDate'] as int?,
      priority: CardPriority.fromString(json['priority'] as String?),
      labels: (json['labels'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      checklist: (json['checklist'] as List<dynamic>? ?? [])
          .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      colorValue: json['color'] as int?,
    );
  }

  bool matchesSearch(String query, {List<KanbanLabel> customLabels = const []}) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if (title.toLowerCase().contains(q)) return true;
    if (description?.toLowerCase().contains(q) ?? false) return true;
    for (final item in checklist) {
      if (item.text.toLowerCase().contains(q)) return true;
    }
    for (final key in labels) {
      final label = findKanbanLabel(key, customLabels);
      if (label != null && label.name.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}