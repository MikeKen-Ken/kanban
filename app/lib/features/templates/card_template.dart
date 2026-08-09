import '../../models/kanban_models.dart';
import '../kanban/kanban_labels.dart';

/// 可同步的卡片模板。图片附件不进入模板，避免多个卡片共享同一二进制标识。
class CardTemplate {
  const CardTemplate({
    required this.id,
    required this.name,
    required this.title,
    this.description,
    this.priority = CardPriority.none,
    this.labels = const [],
    this.checklist = const [],
    this.recurrence = CardRecurrence.none,
    this.recurrenceInterval = 1,
    this.colorValue,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String title;
  final String? description;
  final CardPriority priority;
  final List<String> labels;
  final List<String> checklist;
  final CardRecurrence recurrence;
  final int recurrenceInterval;
  final int? colorValue;
  final int updatedAt;

  factory CardTemplate.fromCard({
    required String id,
    required String name,
    required KanbanCard card,
    required int updatedAt,
  }) {
    return CardTemplate(
      id: id,
      name: name,
      title: card.title,
      description: card.description,
      priority: card.priority,
      labels: [...card.labels],
      checklist: [for (final item in card.checklist) item.text],
      recurrence: card.recurrence,
      recurrenceInterval: card.recurrenceInterval,
      colorValue: card.colorValue,
      updatedAt: updatedAt,
    );
  }

  KanbanCard createCard({
    required String cardId,
    required int createdAt,
    required List<String> checklistIds,
    int order = 0,
  }) {
    if (checklistIds.length != checklist.length) {
      throw ArgumentError('子任务标识数量必须与模板子任务数量一致');
    }
    return KanbanCard(
      id: cardId,
      title: title,
      description: description,
      order: order,
      createdAt: createdAt,
      priority: priority,
      labels: [...labels],
      checklist: [
        for (var i = 0; i < checklist.length; i++)
          ChecklistItem(id: checklistIds[i], text: checklist[i]),
      ],
      recurrence: recurrence,
      recurrenceSeriesId: recurrence == CardRecurrence.none ? null : cardId,
      recurrenceInterval:
          recurrence == CardRecurrence.none ? 1 : recurrenceInterval,
      colorValue: colorValue,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'title': title,
        if (description != null) 'description': description,
        if (priority != CardPriority.none) 'priority': priority.name,
        if (labels.isNotEmpty) 'labels': labels,
        if (checklist.isNotEmpty) 'checklist': checklist,
        if (recurrence != CardRecurrence.none) 'recurrence': recurrence.name,
        if (recurrence != CardRecurrence.none && recurrenceInterval != 1)
          'recurrenceInterval': recurrenceInterval,
        if (colorValue != null) 'color': colorValue,
        'updatedAt': updatedAt,
      };

  factory CardTemplate.fromJson(Map<String, dynamic> json) {
    return CardTemplate(
      id: json['id'] as String,
      name: json['name'] as String? ?? '未命名模板',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      priority: CardPriority.fromString(json['priority'] as String?),
      labels: (json['labels'] as List<dynamic>? ?? [])
          .map((value) => value as String)
          .toList(),
      checklist: (json['checklist'] as List<dynamic>? ?? [])
          .map((value) => value as String)
          .toList(),
      recurrence: CardRecurrence.fromString(json['recurrence'] as String?),
      recurrenceInterval: normalizeRecurrenceInterval(
        json['recurrenceInterval'] as int?,
      ),
      colorValue: json['color'] as int?,
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }
}
