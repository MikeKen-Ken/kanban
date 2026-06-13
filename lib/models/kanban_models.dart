import 'dart:convert';

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

  static KanbanBoard empty({required String id, String title = '我的看板'}) {
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
          title: '已完成',
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
  });

  final String id;
  final String title;
  final int order;
  final List<KanbanCard> cards;

  KanbanColumn copyWith({
    String? id,
    String? title,
    int? order,
    List<KanbanCard>? cards,
  }) {
    return KanbanColumn(
      id: id ?? this.id,
      title: title ?? this.title,
      order: order ?? this.order,
      cards: cards ?? this.cards,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'order': order,
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  factory KanbanColumn.fromJson(Map<String, dynamic> json) {
    return KanbanColumn(
      id: json['id'] as String,
      title: json['title'] as String,
      order: json['order'] as int? ?? 0,
      cards: (json['cards'] as List<dynamic>? ?? [])
          .map((e) => KanbanCard.fromJson(e as Map<String, dynamic>))
          .toList(),
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
  });

  final String id;
  final String title;
  final String? description;
  final int order;
  final int createdAt;

  KanbanCard copyWith({
    String? id,
    String? title,
    String? description,
    int? order,
    int? createdAt,
  }) {
    return KanbanCard(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'order': order,
        'createdAt': createdAt,
      };

  factory KanbanCard.fromJson(Map<String, dynamic> json) {
    return KanbanCard(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      order: json['order'] as int? ?? 0,
      createdAt: json['createdAt'] as int? ?? 0,
    );
  }
}
