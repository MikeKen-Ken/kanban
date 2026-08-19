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

  /// 默认「收件箱」列 id（采集缓冲，避免打断进行中的流程列）
  static const defaultInboxColumnId = 'inbox';

  /// 默认「收件箱」列标题
  static const defaultInboxColumnTitle = '收件箱';

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
        KanbanColumn(
          id: defaultInboxColumnId,
          title: defaultInboxColumnTitle,
          order: 6,
          cards: [],
        ),
      ],
    );
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

/// 卡片通用文件附件元数据（脚本、文档、TXT 等；二进制存于 attachments/ 目录）
class CardFileAttachment {
  CardFileAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.order,
    required this.createdAt,
    this.size = 0,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int order;
  final int createdAt;
  final int size;

  CardFileAttachment copyWith({
    String? id,
    String? fileName,
    String? mimeType,
    int? order,
    int? createdAt,
    int? size,
  }) {
    return CardFileAttachment(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      size: size ?? this.size,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'mimeType': mimeType,
        'order': order,
        'createdAt': createdAt,
        if (size > 0) 'size': size,
      };

  factory CardFileAttachment.fromJson(Map<String, dynamic> json) {
    return CardFileAttachment(
      id: json['id'] as String,
      fileName: json['fileName'] as String? ?? 'file.bin',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      order: json['order'] as int? ?? 0,
      createdAt: json['createdAt'] as int? ?? 0,
      size: json['size'] as int? ?? 0,
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
    int recurrenceInterval = 1,
    this.priority = CardPriority.none,
    this.labels = const [],
    this.checklist = const [],
    this.verificationFeedback = const [],
    this.attachments = const [],
    this.fileAttachments = const [],
    this.links = const [],
    this.blockedByIds = const [],
    this.relatedIds = const [],
    this.commitRef,
    this.agentEngine,
    this.agentModelId,
    this.agentModelParamValues,
    this.agentAllowDirtyWorkspace,
    this.agentEnableSandbox,
    this.agentConversationMarkdown,
    this.colorValue,
    this.conflictSide,
    this.conflictColumnId,
    this.conflictDeleted = false,
  })  : recurrenceInterval = normalizeRecurrenceInterval(recurrenceInterval),
        updatedAt = updatedAt ?? createdAt;

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

  /// 重复间隔：每 N 天/周/月；旧数据缺省视为 1。
  final int recurrenceInterval;
  final CardPriority priority;
  final List<String> labels;
  final List<ChecklistItem> checklist;

  /// 验证反馈项（结构与子任务清单相同：可勾选条目）
  final List<ChecklistItem> verificationFeedback;
  final List<CardAttachment> attachments;

  /// 通用文件附件（脚本、文档、TXT 等）
  final List<CardFileAttachment> fileAttachments;

  /// 外链书签
  final List<CardLink> links;

  /// 阻塞本卡的前置卡片 id（依赖）；前置未完成时本卡应视为被阻塞
  final List<String> blockedByIds;

  /// 关联卡片 id（无先后关系，仅追溯/导航；写入本侧，不会自动回链）
  final List<String> relatedIds;

  /// 完成该任务时对应的 Git 提交号（写入时收成 7 位短哈希）
  final String? commitRef;

  /// Agent 引擎覆盖：`cursor` / `codex`；null 表示沿用工作台。
  final String? agentEngine;

  /// Agent 模型 id 覆盖；null 表示沿用工作台。
  final String? agentModelId;

  /// 已显式选择的模型参数（如 fast / reasoning_effort / context）；空或 null 表示沿用工作台。
  final Map<String, String>? agentModelParamValues;

  /// 本卡是否允许在未提交改动的工作区领取；null 表示沿用工作台（默认失败）。
  final bool? agentAllowDirtyWorkspace;

  /// 本卡是否开启 Agent 沙箱；null 表示沿用工作台（默认关闭）。
  final bool? agentEnableSandbox;

  /// 与本卡绑定的 Agent 对话记录。Markdown 正文随卡片和 WebDAV 同步。
  final String? agentConversationMarkdown;

  /// 卡片背景色 ARGB；null 使用默认 Card 样式
  final int? colorValue;

  /// 冲突时另一侧完整快照（不再嵌套 conflictSide）
  final KanbanCard? conflictSide;

  /// 冲突侧卡片所在列 id
  final String? conflictColumnId;

  /// 冲突侧表示「删除意图」
  final bool conflictDeleted;

  static const maxAttachments = 9;
  static const maxFileAttachments = 20;
  static const agentConversationFileName = 'Agent 对话.md';

  bool get hasConflict => conflictSide != null || conflictDeleted;

  int get checklistDone => checklist.where((item) => item.completed).length;

  bool get hasChecklist => checklist.isNotEmpty;

  int get verificationFeedbackDone =>
      verificationFeedback.where((item) => item.completed).length;

  bool get hasVerificationFeedback => verificationFeedback.isNotEmpty;

  bool get hasAttachments => attachments.isNotEmpty;

  bool get hasFileAttachments => fileAttachments.isNotEmpty;

  bool get hasLinks => links.isNotEmpty;

  bool get hasBlockedBy => blockedByIds.isNotEmpty;

  bool get hasRelated => relatedIds.isNotEmpty;

  bool get hasRelations => hasBlockedBy || hasRelated;

  List<CardAttachment> get sortedAttachments {
    final list = [...attachments]..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  List<CardFileAttachment> get sortedFileAttachments {
    final list = [...fileAttachments]
      ..sort((a, b) => a.order.compareTo(b.order));
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
    Object? description = _sentinel,
    int? order,
    int? createdAt,
    int? updatedAt,
    bool? completed,
    Object? completedAt = _sentinel,
    Object? dueDate = _sentinel,
    Object? reminderAt = _sentinel,
    CardRecurrence? recurrence,
    Object? recurrenceSeriesId = _sentinel,
    int? recurrenceInterval,
    CardPriority? priority,
    List<String>? labels,
    List<ChecklistItem>? checklist,
    List<ChecklistItem>? verificationFeedback,
    List<CardAttachment>? attachments,
    List<CardFileAttachment>? fileAttachments,
    List<CardLink>? links,
    List<String>? blockedByIds,
    List<String>? relatedIds,
    Object? commitRef = _sentinel,
    Object? agentEngine = _sentinel,
    Object? agentModelId = _sentinel,
    Object? agentModelParamValues = _sentinel,
    Object? agentAllowDirtyWorkspace = _sentinel,
    Object? agentEnableSandbox = _sentinel,
    Object? agentConversationMarkdown = _sentinel,
    Object? colorValue = _sentinel,
    Object? conflictSide = _sentinel,
    Object? conflictColumnId = _sentinel,
    bool? conflictDeleted,
    bool clearConflict = false,
  }) {
    return KanbanCard(
      id: id ?? this.id,
      title: title ?? this.title,
      description:
          description == _sentinel ? this.description : description as String?,
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
      recurrenceInterval: recurrenceInterval ?? this.recurrenceInterval,
      priority: priority ?? this.priority,
      labels: labels ?? this.labels,
      checklist: checklist ?? this.checklist,
      verificationFeedback: verificationFeedback ?? this.verificationFeedback,
      attachments: attachments ?? this.attachments,
      fileAttachments: fileAttachments ?? this.fileAttachments,
      links: links ?? this.links,
      blockedByIds: blockedByIds ?? this.blockedByIds,
      relatedIds: relatedIds ?? this.relatedIds,
      commitRef: commitRef == _sentinel ? this.commitRef : commitRef as String?,
      agentEngine:
          agentEngine == _sentinel ? this.agentEngine : agentEngine as String?,
      agentModelId: agentModelId == _sentinel
          ? this.agentModelId
          : agentModelId as String?,
      agentModelParamValues: agentModelParamValues == _sentinel
          ? this.agentModelParamValues
          : agentModelParamValues as Map<String, String>?,
      agentAllowDirtyWorkspace: agentAllowDirtyWorkspace == _sentinel
          ? this.agentAllowDirtyWorkspace
          : agentAllowDirtyWorkspace as bool?,
      agentEnableSandbox: agentEnableSandbox == _sentinel
          ? this.agentEnableSandbox
          : agentEnableSandbox as bool?,
      agentConversationMarkdown: agentConversationMarkdown == _sentinel
          ? this.agentConversationMarkdown
          : agentConversationMarkdown as String?,
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
      if (recurrence != CardRecurrence.none && recurrenceInterval != 1)
        'recurrenceInterval': recurrenceInterval,
      if (priority != CardPriority.none) 'priority': priority.name,
      if (labels.isNotEmpty) 'labels': labels,
      if (checklist.isNotEmpty)
        'checklist': checklist.map((c) => c.toJson()).toList(),
      if (verificationFeedback.isNotEmpty)
        'verificationFeedback':
            verificationFeedback.map((c) => c.toJson()).toList(),
      if (attachments.isNotEmpty)
        'attachments': attachments.map((a) => a.toJson()).toList(),
      if (fileAttachments.isNotEmpty)
        'fileAttachments': fileAttachments.map((a) => a.toJson()).toList(),
      if (links.isNotEmpty)
        'links': links.map((link) => link.toJson()).toList(),
      if (blockedByIds.isNotEmpty) 'blockedByIds': blockedByIds,
      if (relatedIds.isNotEmpty) 'relatedIds': relatedIds,
      if (commitRef != null && commitRef!.isNotEmpty) 'commitRef': commitRef,
      if (agentEngine != null && agentEngine!.isNotEmpty)
        'agentEngine': agentEngine,
      if (agentModelId != null && agentModelId!.isNotEmpty)
        'agentModelId': agentModelId,
      if (agentModelParamValues != null && agentModelParamValues!.isNotEmpty)
        'agentModelParamValues': agentModelParamValues,
      if (agentAllowDirtyWorkspace != null)
        'agentAllowDirtyWorkspace': agentAllowDirtyWorkspace,
      if (agentEnableSandbox != null) 'agentEnableSandbox': agentEnableSandbox,
      if (agentConversationMarkdown != null &&
          agentConversationMarkdown!.isNotEmpty)
        'agentConversationMarkdown': agentConversationMarkdown,
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
      recurrenceInterval: normalizeRecurrenceInterval(
        json['recurrenceInterval'] as int?,
      ),
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
      fileAttachments: (json['fileAttachments'] as List<dynamic>? ?? [])
          .map((e) => CardFileAttachment.fromJson(e as Map<String, dynamic>))
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
      commitRef: json['commitRef'] as String?,
      agentEngine: json['agentEngine'] as String?,
      agentModelId: json['agentModelId'] as String?,
      agentModelParamValues: _stringMap(json['agentModelParamValues']),
      agentAllowDirtyWorkspace: json['agentAllowDirtyWorkspace'] as bool?,
      agentEnableSandbox: json['agentEnableSandbox'] as bool?,
      agentConversationMarkdown: json['agentConversationMarkdown'] as String?,
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
    if (commitRef?.toLowerCase().contains(q) ?? false) return true;
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
    for (final attachment in attachments) {
      if (attachment.fileName.toLowerCase().contains(q)) return true;
    }
    for (final file in fileAttachments) {
      if (file.fileName.toLowerCase().contains(q)) return true;
    }
    for (final key in labels) {
      final label = findKanbanLabel(key, customLabels);
      if (label == null) continue;
      if (label.name.toLowerCase().contains(q)) return true;
      final desc = label.description;
      if (desc != null && desc.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  /// Worker peek / get_card 用的覆盖字段；未选择时不输出。
  Map<String, dynamic> agentDispatchOverridePayload() => {
        if (agentEngine != null && agentEngine!.trim().isNotEmpty)
          'agentEngine': agentEngine!.trim(),
        if (agentModelId != null && agentModelId!.trim().isNotEmpty)
          'agentModelId': agentModelId!.trim(),
        if (agentModelParamValues != null && agentModelParamValues!.isNotEmpty)
          'agentModelParamValues': agentModelParamValues,
        if (agentAllowDirtyWorkspace != null)
          'agentAllowDirtyWorkspace': agentAllowDirtyWorkspace,
        if (agentEnableSandbox != null)
          'agentEnableSandbox': agentEnableSandbox,
      };
}

Map<String, String>? _stringMap(Object? raw) {
  if (raw is! Map) return null;
  final map = <String, String>{};
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value == null) continue;
    final text = '$value'.trim();
    if (text.isEmpty) continue;
    map['${entry.key}'] = text;
  }
  return map.isEmpty ? null : map;
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

  /// 详情菜单展示顺序：周期在前，「不重复」最后。
  static const List<CardRecurrence> menuOrder = [
    CardRecurrence.daily,
    CardRecurrence.weekly,
    CardRecurrence.monthly,
    CardRecurrence.none,
  ];

  /// 间隔选择器单位文案（天/周/月）。
  String get intervalUnitLabel => switch (this) {
        CardRecurrence.none => '',
        CardRecurrence.daily => '天',
        CardRecurrence.weekly => '周',
        CardRecurrence.monthly => '月',
      };

  /// 「每 N 天/周/月」展示文案；N=1 时回落到每天/每周/每月。
  String intervalLabel(int interval) {
    final n = normalizeRecurrenceInterval(interval);
    if (this == CardRecurrence.none) return label;
    if (n == 1) return label;
    return '每$n$intervalUnitLabel';
  }

  static CardRecurrence fromString(String? value) {
    return CardRecurrence.values.firstWhere(
      (item) => item.name == value,
      orElse: () => CardRecurrence.none,
    );
  }
}

/// 重复间隔安全默认：缺失或非法值视为 1。
int normalizeRecurrenceInterval(int? value) {
  if (value == null || value < 1) return 1;
  return value;
}
