import 'dart:convert';

import '../features/kanban/kanban_labels.dart';

class KanbanBoard {
  KanbanBoard({
    required this.id,
    required this.title,
    required this.columns,
    required this.updatedAt,
    required this.revision,
    this.conflictTitle,
  });

  final String id;
  final String title;
  final List<KanbanColumn> columns;
  final int updatedAt;
  final int revision;

  /// 板标题冲突时的另一侧标题
  final String? conflictTitle;

  bool get hasConflict =>
      conflictTitle != null ||
      columns.any((c) => c.cards.any((card) => card.hasConflict));

  KanbanBoard copyWith({
    String? id,
    String? title,
    List<KanbanColumn>? columns,
    int? updatedAt,
    int? revision,
    Object? conflictTitle = _boardSentinel,
    bool clearConflictTitle = false,
  }) {
    return KanbanBoard(
      id: id ?? this.id,
      title: title ?? this.title,
      columns: columns ?? this.columns,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
      conflictTitle: clearConflictTitle
          ? null
          : (conflictTitle == _boardSentinel
              ? this.conflictTitle
              : conflictTitle as String?),
    );
  }

  static const _boardSentinel = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'columns': columns.map((c) => c.toJson()).toList(),
        'updatedAt': updatedAt,
        'revision': revision,
        if (conflictTitle != null) 'conflictTitle': conflictTitle,
      };

  /// 元数据 JSON（不含卡片），配合 columns/{id}.json 使用
  Map<String, dynamic> toMetadataJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt,
        'revision': revision,
        'version': 2,
        'columns': columns.map((c) => {'id': c.id, 'order': c.order}).toList(),
        if (conflictTitle != null) 'conflictTitle': conflictTitle,
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
      conflictTitle: json['conflictTitle'] as String?,
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
      conflictTitle: json['conflictTitle'] as String?,
    );
  }

  /// 默认「待返工」列 id（新建看板）
  static const defaultReworkColumnId = 'rework';

  /// 默认「待返工」列标题
  static const defaultReworkColumnTitle = '待返工';

  /// 默认「待验证」列标题
  static const defaultVerifyColumnTitle = '待验证';

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
          id: 'blocked',
          title: '阻塞中',
          order: 2,
          cards: [],
        ),
        KanbanColumn(
          id: 'verify',
          title: defaultVerifyColumnTitle,
          order: 3,
          cards: [],
        ),
        KanbanColumn(
          id: defaultReworkColumnId,
          title: defaultReworkColumnTitle,
          order: 4,
          cards: [],
        ),
        KanbanColumn(
          id: 'done',
          title: doneColumnTitle,
          order: 5,
          cards: [],
        ),
      ],
    );
  }

  /// 确保存在「待返工」列，并尽量放在待验证之后、已完成之前。
  ///
  /// 按标题优先识别；多个同名「待返工」会合并到优先列（优先默认 id，否则第一个）并删除多余列。
  /// 仅当既无同名标题、也无默认 id 时才新建一次。
  /// 若列集合与顺序已符合目标，返回 `this`（可做引用相等判断）。
  KanbanBoard ensureReworkColumn({String doneColumnTitle = '已完成'}) {
    var sorted = [...columns]..sort((a, b) => a.order.compareTo(b.order));
    var mutated = false;

    final titleMatchIndexes = <int>[
      for (var i = 0; i < sorted.length; i++)
        if (sorted[i].title == defaultReworkColumnTitle) i,
    ];
    if (titleMatchIndexes.length > 1) {
      final keepIndex = titleMatchIndexes.firstWhere(
        (i) => sorted[i].id == defaultReworkColumnId,
        orElse: () => titleMatchIndexes.first,
      );
      final keep = sorted[keepIndex];
      final seenCardIds = <String>{for (final card in keep.cards) card.id};
      final mergedCards = [...keep.cards];
      final removeIds = <String>{};
      for (final i in titleMatchIndexes) {
        if (i == keepIndex) continue;
        removeIds.add(sorted[i].id);
        for (final card in sorted[i].cards) {
          if (seenCardIds.add(card.id)) {
            mergedCards.add(card);
          }
        }
      }
      final normalizedCards = [
        for (var i = 0; i < mergedCards.length; i++)
          mergedCards[i].copyWith(order: i),
      ];
      sorted = [
        for (final col in sorted)
          if (col.id == keep.id)
            keep.copyWith(cards: normalizedCards)
          else if (!removeIds.contains(col.id))
            col,
      ];
      mutated = true;
    }

    // 标题优先，其次默认 id（避免「标题已改名的 rework」抢在真正的「待返工」之前）。
    var existingIndex = sorted.indexWhere(
      (col) => col.title == defaultReworkColumnTitle,
    );
    if (existingIndex < 0) {
      existingIndex = sorted.indexWhere(
        (col) => col.id == defaultReworkColumnId,
      );
    }

    final desiredIndex = _desiredReworkInsertIndex(
      sorted,
      doneColumnTitle: doneColumnTitle,
      existingIndex: existingIndex,
    );

    if (existingIndex >= 0) {
      if (existingIndex == desiredIndex) {
        final alreadyNormalized = sorted.asMap().entries.every(
              (entry) => entry.value.order == entry.key,
            );
        if (alreadyNormalized && !mutated) return this;
        return copyWith(
          columns: [
            for (var i = 0; i < sorted.length; i++)
              sorted[i].copyWith(order: i),
          ],
        );
      }
      final rework = sorted.removeAt(existingIndex);
      final insertAt = desiredIndex.clamp(0, sorted.length);
      sorted.insert(insertAt, rework);
      return copyWith(
        columns: [
          for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(order: i),
        ],
      );
    }

    // 防御：同名已存在时绝不新建（即使 id 查找未命中）。
    if (sorted.any((col) => col.title == defaultReworkColumnTitle)) {
      return mutated
          ? copyWith(
              columns: [
                for (var i = 0; i < sorted.length; i++)
                  sorted[i].copyWith(order: i),
              ],
            )
          : this;
    }

    final insertAt = desiredIndex.clamp(0, sorted.length);
    sorted.insert(
      insertAt,
      KanbanColumn(
        id: defaultReworkColumnId,
        title: defaultReworkColumnTitle,
        order: insertAt,
        cards: const [],
      ),
    );
    return copyWith(
      columns: [
        for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(order: i),
      ],
    );
  }

  /// 计算「待返工」应插入的下标：待验证之后；否则已完成之前；否则末尾。
  static int _desiredReworkInsertIndex(
    List<KanbanColumn> sorted, {
    required String doneColumnTitle,
    required int existingIndex,
  }) {
    final withoutRework = [
      for (var i = 0; i < sorted.length; i++)
        if (i != existingIndex) sorted[i],
    ];
    final verifyIndex = withoutRework.indexWhere(
      (col) => col.title == defaultVerifyColumnTitle || col.id == 'verify',
    );
    if (verifyIndex >= 0) return verifyIndex + 1;
    final doneIndex = withoutRework.indexWhere(
      (col) => col.title == doneColumnTitle || col.id == 'done',
    );
    if (doneIndex >= 0) return doneIndex;
    return withoutRework.length;
  }

  String toJsonString() => jsonEncode(toJson());

  factory KanbanBoard.fromJsonString(String source) {
    return KanbanBoard.fromJson(jsonDecode(source) as Map<String, dynamic>);
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

/// 卡片图片附件元数据（二进制存于 attachments/ 目录）
class CardAttachment {
  CardAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.order,
    required this.createdAt,
    this.width,
    this.height,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int order;
  final int createdAt;
  final int? width;
  final int? height;

  CardAttachment copyWith({
    String? id,
    String? fileName,
    String? mimeType,
    int? order,
    int? createdAt,
    int? width,
    int? height,
  }) {
    return CardAttachment(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'mimeType': mimeType,
        'order': order,
        'createdAt': createdAt,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };

  factory CardAttachment.fromJson(Map<String, dynamic> json) {
    return CardAttachment(
      id: json['id'] as String,
      fileName: json['fileName'] as String? ?? 'image.jpg',
      mimeType: json['mimeType'] as String? ?? 'image/jpeg',
      order: json['order'] as int? ?? 0,
      createdAt: json['createdAt'] as int? ?? 0,
      width: json['width'] as int?,
      height: json['height'] as int?,
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

/// 卡片外链（网页书签），与图片附件分开存储。
class CardLink {
  CardLink({
    required this.id,
    required this.url,
    required this.order,
    required this.createdAt,
    this.title = '',
  });

  final String id;
  final String url;
  final String title;
  final int order;
  final int createdAt;

  CardLink copyWith({
    String? id,
    String? url,
    String? title,
    int? order,
    int? createdAt,
  }) {
    return CardLink(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get displayTitle {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return url;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        if (title.isNotEmpty) 'title': title,
        'order': order,
        'createdAt': createdAt,
      };

  factory CardLink.fromJson(Map<String, dynamic> json) {
    return CardLink(
      id: json['id'] as String,
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      order: json['order'] as int? ?? 0,
      createdAt: json['createdAt'] as int? ?? 0,
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
    int? updatedAt,
    this.completed = false,
    this.completedAt,
    this.dueDate,
    this.reminderAt,
    this.recurrence = CardRecurrence.none,
    this.recurrenceSeriesId,
    this.priority = CardPriority.none,
    this.labels = const [],
    this.checklist = const [],
    this.verificationFeedback = const [],
    this.attachments = const [],
    this.links = const [],
    this.blockedByIds = const [],
    this.relatedIds = const [],
    this.colorValue,
    this.conflictSide,
    this.conflictColumnId,
    this.conflictDeleted = false,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String title;
  final String? description;
  final int order;
  final int createdAt;
  final int updatedAt;
  final bool completed;
  final int? completedAt;
  final int? dueDate;
  final int? reminderAt;
  final CardRecurrence recurrence;
  final String? recurrenceSeriesId;
  final CardPriority priority;
  final List<String> labels;
  final List<ChecklistItem> checklist;

  /// 验证反馈项（结构与子任务清单相同：可勾选条目）
  final List<ChecklistItem> verificationFeedback;
  final List<CardAttachment> attachments;

  /// 外链书签
  final List<CardLink> links;

  /// 阻塞本卡的前置卡片 id（依赖）；前置未完成时本卡应视为被阻塞
  final List<String> blockedByIds;

  /// 关联卡片 id（无先后关系，仅追溯/导航；写入本侧，不会自动回链）
  final List<String> relatedIds;

  /// 卡片背景色 ARGB；null 使用默认 Card 样式
  final int? colorValue;

  /// 冲突时另一侧完整快照（不再嵌套 conflictSide）
  final KanbanCard? conflictSide;

  /// 冲突侧卡片所在列 id
  final String? conflictColumnId;

  /// 冲突侧表示「删除意图」
  final bool conflictDeleted;

  static const maxAttachments = 9;

  bool get hasConflict => conflictSide != null || conflictDeleted;

  int get checklistDone => checklist.where((item) => item.completed).length;

  bool get hasChecklist => checklist.isNotEmpty;

  int get verificationFeedbackDone =>
      verificationFeedback.where((item) => item.completed).length;

  bool get hasVerificationFeedback => verificationFeedback.isNotEmpty;

  bool get hasAttachments => attachments.isNotEmpty;

  bool get hasLinks => links.isNotEmpty;

  bool get hasRelations => blockedByIds.isNotEmpty || relatedIds.isNotEmpty;

  List<CardAttachment> get sortedAttachments {
    final list = [...attachments]..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  List<CardLink> get sortedLinks {
    final list = [...links]..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  CardAttachment? get coverAttachment =>
      sortedAttachments.isEmpty ? null : sortedAttachments.first;

  KanbanCard copyWith({
    String? id,
    String? title,
    String? description,
    int? order,
    int? createdAt,
    int? updatedAt,
    bool? completed,
    Object? completedAt = _sentinel,
    Object? dueDate = _sentinel,
    Object? reminderAt = _sentinel,
    CardRecurrence? recurrence,
    Object? recurrenceSeriesId = _sentinel,
    CardPriority? priority,
    List<String>? labels,
    List<ChecklistItem>? checklist,
    List<ChecklistItem>? verificationFeedback,
    List<CardAttachment>? attachments,
    List<CardLink>? links,
    List<String>? blockedByIds,
    List<String>? relatedIds,
    Object? colorValue = _sentinel,
    Object? conflictSide = _sentinel,
    Object? conflictColumnId = _sentinel,
    bool? conflictDeleted,
    bool clearConflict = false,
  }) {
    return KanbanCard(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completed: completed ?? this.completed,
      completedAt:
          completedAt == _sentinel ? this.completedAt : completedAt as int?,
      dueDate: dueDate == _sentinel ? this.dueDate : dueDate as int?,
      reminderAt:
          reminderAt == _sentinel ? this.reminderAt : reminderAt as int?,
      recurrence: recurrence ?? this.recurrence,
      recurrenceSeriesId: recurrenceSeriesId == _sentinel
          ? this.recurrenceSeriesId
          : recurrenceSeriesId as String?,
      priority: priority ?? this.priority,
      labels: labels ?? this.labels,
      checklist: checklist ?? this.checklist,
      verificationFeedback: verificationFeedback ?? this.verificationFeedback,
      attachments: attachments ?? this.attachments,
      links: links ?? this.links,
      blockedByIds: blockedByIds ?? this.blockedByIds,
      relatedIds: relatedIds ?? this.relatedIds,
      colorValue:
          colorValue == _sentinel ? this.colorValue : colorValue as int?,
      conflictSide: clearConflict
          ? null
          : (conflictSide == _sentinel
              ? this.conflictSide
              : conflictSide as KanbanCard?),
      conflictColumnId: clearConflict
          ? null
          : (conflictColumnId == _sentinel
              ? this.conflictColumnId
              : conflictColumnId as String?),
      conflictDeleted:
          clearConflict ? false : (conflictDeleted ?? this.conflictDeleted),
    );
  }

  static const _sentinel = Object();

  /// 序列化时去掉嵌套冲突，避免无限递归
  Map<String, dynamic> toJson({bool includeConflict = true}) {
    final map = <String, dynamic>{
      'id': id,
      'title': title,
      'description': description,
      'order': order,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'completed': completed,
      if (completedAt != null) 'completedAt': completedAt,
      if (dueDate != null) 'dueDate': dueDate,
      if (reminderAt != null) 'reminderAt': reminderAt,
      if (recurrence != CardRecurrence.none) 'recurrence': recurrence.name,
      if (recurrenceSeriesId != null) 'recurrenceSeriesId': recurrenceSeriesId,
      if (priority != CardPriority.none) 'priority': priority.name,
      if (labels.isNotEmpty) 'labels': labels,
      if (checklist.isNotEmpty)
        'checklist': checklist.map((c) => c.toJson()).toList(),
      if (verificationFeedback.isNotEmpty)
        'verificationFeedback':
            verificationFeedback.map((c) => c.toJson()).toList(),
      if (attachments.isNotEmpty)
        'attachments': attachments.map((a) => a.toJson()).toList(),
      if (links.isNotEmpty) 'links': links.map((link) => link.toJson()).toList(),
      if (blockedByIds.isNotEmpty) 'blockedByIds': blockedByIds,
      if (relatedIds.isNotEmpty) 'relatedIds': relatedIds,
      if (colorValue != null) 'color': colorValue,
    };
    if (includeConflict) {
      if (conflictSide != null) {
        map['conflictSide'] = conflictSide!.toJson(includeConflict: false);
      }
      if (conflictColumnId != null) {
        map['conflictColumnId'] = conflictColumnId;
      }
      if (conflictDeleted) map['conflictDeleted'] = true;
    }
    return map;
  }

  factory KanbanCard.fromJson(Map<String, dynamic> json) {
    final sideRaw = json['conflictSide'] as Map<String, dynamic>?;
    return KanbanCard(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      order: json['order'] as int? ?? 0,
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? json['createdAt'] as int? ?? 0,
      completed: json['completed'] as bool? ?? false,
      completedAt: json['completedAt'] as int?,
      dueDate: json['dueDate'] as int?,
      reminderAt: json['reminderAt'] as int?,
      recurrence: CardRecurrence.fromString(json['recurrence'] as String?),
      recurrenceSeriesId: json['recurrenceSeriesId'] as String?,
      priority: CardPriority.fromString(json['priority'] as String?),
      labels: (json['labels'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      checklist: (json['checklist'] as List<dynamic>? ?? [])
          .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      verificationFeedback:
          (json['verificationFeedback'] as List<dynamic>? ?? [])
              .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
              .toList(),
      attachments: (json['attachments'] as List<dynamic>? ?? [])
          .map((e) => CardAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
      links: (json['links'] as List<dynamic>? ?? [])
          .map((e) => CardLink.fromJson(e as Map<String, dynamic>))
          .toList(),
      blockedByIds: (json['blockedByIds'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      relatedIds: (json['relatedIds'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      colorValue: json['color'] as int?,
      conflictSide: sideRaw == null ? null : KanbanCard.fromJson(sideRaw),
      conflictColumnId: json['conflictColumnId'] as String?,
      conflictDeleted: json['conflictDeleted'] as bool? ?? false,
    );
  }

  bool matchesSearch(String query,
      {List<KanbanLabel> customLabels = const []}) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if (title.toLowerCase().contains(q)) return true;
    if (description?.toLowerCase().contains(q) ?? false) return true;
    for (final item in checklist) {
      if (item.text.toLowerCase().contains(q)) return true;
    }
    for (final item in verificationFeedback) {
      if (item.text.toLowerCase().contains(q)) return true;
    }
    for (final link in links) {
      if (link.title.toLowerCase().contains(q)) return true;
      if (link.url.toLowerCase().contains(q)) return true;
    }
    for (final key in labels) {
      final label = findKanbanLabel(key, customLabels);
      if (label != null && label.name.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

enum CardRecurrence {
  none,
  daily,
  weekly,
  monthly;

  String get label => switch (this) {
        CardRecurrence.none => '不重复',
        CardRecurrence.daily => '每天',
        CardRecurrence.weekly => '每周',
        CardRecurrence.monthly => '每月',
      };

  static CardRecurrence fromString(String? value) {
    return CardRecurrence.values.firstWhere(
      (item) => item.name == value,
      orElse: () => CardRecurrence.none,
    );
  }
}
