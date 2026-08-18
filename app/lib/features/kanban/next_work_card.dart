import '../../models/kanban_models.dart';
import 'move_to_rework_on_new_feedback.dart';
import 'verify_column.dart';

/// 默认「待办」列标题（与 [KanbanBoard.empty] 一致）。
const defaultTodoColumnTitle = '待办';

/// 默认「待办」列 id。
const defaultTodoColumnId = 'todo';

/// 有未完成验证反馈时视为返工模式。
bool isReworkWorkMode(KanbanCard card) =>
    card.verificationFeedback.any((item) => !item.completed);

/// 解析「待办」列：标题优先，再回退默认 id。
KanbanColumn? findTodoColumn(Iterable<KanbanColumn> columns) {
  final list =
      columns is List<KanbanColumn> ? columns : List<KanbanColumn>.of(columns);
  for (final col in list) {
    if (col.title == defaultTodoColumnTitle) return col;
  }
  for (final col in list) {
    if (col.id == defaultTodoColumnId) return col;
  }
  return null;
}

/// 列内按 `updatedAt` 降序取最新未完成卡；同时间戳再比 `createdAt`。
KanbanCard? pickLatestIncompleteCard(Iterable<KanbanCard> cards) {
  KanbanCard? best;
  for (final card in cards) {
    if (card.completed) continue;
    if (best == null ||
        card.updatedAt > best.updatedAt ||
        (card.updatedAt == best.updatedAt &&
            card.createdAt > best.createdAt)) {
      best = card;
    }
  }
  return best;
}

/// 「待返工」优先，其次「进行中」滞留卡，最后「待办」。
///
/// 领取后卡会停在「进行中」。会话失败、崩溃或未声明完成时，Max 必须仍能领到这些卡，
/// 否则 Worker 会把空待办当成批次结束，看板里留下无 Agent 的进行中卡片。
({KanbanColumn column, KanbanCard card, String sourceColumn})? pickNextWorkCard(
  KanbanBoard board,
) {
  final rework = findReworkColumn(board.columns);
  if (rework != null) {
    final card = pickLatestIncompleteCard(rework.cards);
    if (card != null) {
      return (
        column: rework,
        card: card,
        sourceColumn: KanbanBoard.defaultReworkColumnTitle,
      );
    }
  }

  final doing = findDoingColumn(board.columns);
  if (doing != null) {
    final card = pickLatestIncompleteCard(doing.cards);
    if (card != null) {
      return (
        column: doing,
        card: card,
        sourceColumn: defaultDoingColumnTitle,
      );
    }
  }

  final todo = findTodoColumn(board.columns);
  if (todo != null) {
    final card = pickLatestIncompleteCard(todo.cards);
    if (card != null) {
      return (column: todo, card: card, sourceColumn: defaultTodoColumnTitle);
    }
  }

  return null;
}

int _countIncompleteCards(KanbanColumn? column) {
  if (column == null) return 0;
  var count = 0;
  for (final card in column.cards) {
    if (!card.completed) count += 1;
  }
  return count;
}

/// 待返工、进行中与待办中未完成卡片数，供调度进度分母估算。
int countWorkQueueCards(KanbanBoard board) {
  return _countIncompleteCards(findReworkColumn(board.columns)) +
      _countIncompleteCards(findDoingColumn(board.columns)) +
      _countIncompleteCards(findTodoColumn(board.columns));
}

/// 实时进度用剩余队列：不含当前正在实施的那张进行中卡。
int countRemainingDispatchQueue(
  KanbanBoard board, {
  required bool hasActiveCard,
}) {
  final total = countWorkQueueCards(board);
  if (!hasActiveCard || total <= 0) return total;
  return total - 1;
}

/// 本轮实施范围（仅文本；附件由 MCP 层内联二进制）。
Map<String, dynamic> buildCardWorkScope(KanbanCard card) {
  final rework = isReworkWorkMode(card);
  return {
    'workMode': rework ? 'rework' : 'normal',
    'workItems': buildCardWorkItems(card),
    if (card.labels.isNotEmpty) 'labels': card.labels,
    if (card.commitRef != null && card.commitRef!.isNotEmpty)
      'commitRef': card.commitRef,
  };
}

/// 本轮应实施的工作项。
///
/// 普通与返工均含标题、备注、未完成 checklist；返工另附未完成验证反馈。
/// 已完成 checklist / 反馈不返回。
List<Map<String, dynamic>> buildCardWorkItems(KanbanCard card) {
  final items = <Map<String, dynamic>>[
    {'kind': 'title', 'text': card.title},
  ];
  final description = card.description?.trim();
  if (description != null && description.isNotEmpty) {
    items.add({'kind': 'description', 'text': description});
  }
  for (final item in card.checklist) {
    if (item.completed) continue;
    items.add({
      'kind': 'checklist',
      'id': item.id,
      'text': item.text,
    });
  }
  for (final item in card.verificationFeedback) {
    if (item.completed) continue;
    items.add({
      'kind': 'verificationFeedback',
      'id': item.id,
      'text': item.text,
    });
  }
  return items;
}

/// 提交信息：返工仅用未完成验证反馈原文；普通用标题、备注与未完成子任务。
String buildCardCommitMessage(KanbanCard card) {
  if (isReworkWorkMode(card)) {
    return [
      for (final item in card.verificationFeedback)
        if (!item.completed) item.text.trim(),
    ].where((text) => text.isNotEmpty).join('\n');
  }

  final title = card.title.trim();
  final description = card.description?.trim();
  final incompleteChecklist = [
    for (final item in card.checklist)
      if (!item.completed && item.text.trim().isNotEmpty)
        '- ${item.text.trim()}',
  ];
  return [
    title,
    if (description != null && description.isNotEmpty) description,
    if (incompleteChecklist.isNotEmpty) incompleteChecklist.join('\n'),
  ].join('\n\n');
}

/// 把所有未完成验证反馈勾为完成；无未完成项时返回 null。
List<ChecklistItem>? markAllIncompleteFeedbackDone(KanbanCard card) {
  if (!card.verificationFeedback.any((item) => !item.completed)) return null;
  return [
    for (final item in card.verificationFeedback)
      item.completed ? item : item.copyWith(completed: true),
  ];
}
