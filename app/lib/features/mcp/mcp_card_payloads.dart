import '../../models/kanban_models.dart';
import '../views/card_reference.dart';

/// 整板列表中的紧凑卡片摘要；详情应按需使用 get_card 读取。
Map<String, dynamic> mcpBoardCardSummary(
  KanbanCard card, {
  bool includeDetails = false,
  int descriptionMax = 120,
}) {
  final payload = <String, dynamic>{
    'id': card.id,
    'title': card.title,
    'completed': card.completed,
    'priority': card.priority.name,
    if (card.dueDate != null) 'dueDate': card.dueDate,
    if (card.labels.isNotEmpty) 'labels': card.labels,
    if (card.hasChecklist)
      'checklist': {
        'done': card.checklistDone,
        'total': card.checklist.length,
      },
    if (card.hasVerificationFeedback)
      'verificationFeedback': {
        'done': card.verificationFeedbackDone,
        'total': card.verificationFeedback.length,
      },
    if (card.attachments.isNotEmpty) 'attachmentCount': card.attachments.length,
    if (card.blockedByIds.isNotEmpty) 'blockedByIds': card.blockedByIds,
    if (card.commitRef != null && card.commitRef!.isNotEmpty)
      'commitRef': card.commitRef,
  };
  if (!includeDetails) return payload;

  final description = card.description;
  if (description != null && description.isNotEmpty) {
    payload['description'] = description.length <= descriptionMax
        ? description
        : '${description.substring(0, descriptionMax)}…';
  }
  if (card.colorValue != null) payload['colorValue'] = card.colorValue;
  if (card.commitRef != null && card.commitRef!.isNotEmpty) {
    payload['commitRef'] = card.commitRef;
  }
  if (card.relatedIds.isNotEmpty) payload['relatedIds'] = card.relatedIds;
  if (card.links.isNotEmpty) {
    payload['links'] = [
      for (final link in card.sortedLinks) link.toJson(),
    ];
  }
  return payload;
}

/// 搜索列表中的卡片摘要；省略正文、清单文本、反馈文本和外链正文。
Map<String, dynamic> mcpCardReferenceSummary(CardReference card) => {
      'projectId': card.projectId,
      if (card.projectName.isNotEmpty) 'projectName': card.projectName,
      'columnId': card.columnId,
      if (card.columnName.isNotEmpty) 'columnName': card.columnName,
      'cardId': card.cardId,
      'title': card.title,
      'completed': card.completed,
      'priority': card.priority,
      if (card.dueDate != null) 'dueDate': card.dueDate,
      if (card.labelIds.isNotEmpty) 'labelIds': card.labelIds,
      if (card.labelNames.isNotEmpty) 'labelNames': card.labelNames,
      if (card.checklistTexts.isNotEmpty)
        'checklistCount': card.checklistTexts.length,
      if (card.verificationFeedbackTexts.isNotEmpty)
        'verificationFeedbackCount': card.verificationFeedbackTexts.length,
      if (card.blockedByIds.isNotEmpty) 'blockedByIds': card.blockedByIds,
      if (card.commitRef != null && card.commitRef!.isNotEmpty)
        'commitRef': card.commitRef,
    };

/// 列表默认返回摘要；显式 detail=full 时才返回完整引用。
Map<String, dynamic> mcpCardReferencePayload(
  CardReference card, {
  required bool full,
}) =>
    full ? card.toJson() : mcpCardReferenceSummary(card);

/// 单卡详情保留完整清单，但不重复返回对应的纯文本摘要。
///
/// 附件只保留计数；二进制/元数据列表请用 list_card_attachments、read_card_attachment。
Map<String, dynamic> mcpCardDetails(CardReference card) {
  final payload = card.toJson();
  final source = card.source;
  if (source is! KanbanCard) return payload;

  if (source.checklist.isNotEmpty) {
    payload.remove('checklistTexts');
    payload['checklist'] = [
      for (final item in source.checklist) item.toJson(),
    ];
  }
  if (source.verificationFeedback.isNotEmpty) {
    payload.remove('verificationFeedbackTexts');
    payload['verificationFeedback'] = [
      for (final item in source.verificationFeedback) item.toJson(),
    ];
  }
  if (source.attachments.isNotEmpty) {
    payload.remove('attachments');
    payload['attachmentCount'] = source.attachments.length;
  }
  if (source.fileAttachments.isNotEmpty) {
    payload.remove('fileAttachments');
    payload['fileAttachmentCount'] = source.fileAttachments.length;
  }
  if (source.attachments.isNotEmpty || source.fileAttachments.isNotEmpty) {
    payload['attachmentsNote'] =
        '附件仅计数；元数据用 list_card_attachments，二进制用 read_card_attachment 按需读取';
  }
  return payload;
}
