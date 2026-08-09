import '../../models/kanban_models.dart';

/// 相对打开详情时的快照，[next] 是否含有新增的验证反馈项（按 id）。
///
/// 改文案、勾选已有项不算新增；仅子任务变更也不影响本判断。
bool hasAddedVerificationFeedbackItems({
  required List<ChecklistItem> original,
  required List<ChecklistItem> next,
}) {
  final originalIds = {for (final item in original) item.id};
  return next.any((item) => !originalIds.contains(item.id));
}

/// 解析「待返工」列：先扫全部列按标题精确匹配，再回退默认 id。
///
/// 存在多个同名「待返工」时取顺序中的第一个，避免误建或误绑到仅 id 匹配、标题已改名的列。
KanbanColumn? findReworkColumn(Iterable<KanbanColumn> columns) {
  final list = columns is List<KanbanColumn>
      ? columns
      : List<KanbanColumn>.of(columns);
  for (final col in list) {
    if (col.title == KanbanBoard.defaultReworkColumnTitle) return col;
  }
  for (final col in list) {
    if (col.id == KanbanBoard.defaultReworkColumnId) return col;
  }
  return null;
}

/// [columnId] 是否对应看板中的「待返工」列。
bool isReworkColumnId({
  required String columnId,
  required Iterable<KanbanColumn> columns,
}) {
  final rework = findReworkColumn(columns);
  if (rework != null) return rework.id == columnId;
  // 列尚未出现在快照时，仍按默认 id 识别。
  return columnId == KanbanBoard.defaultReworkColumnId;
}

/// 是否存在未勾选完成的验证反馈项。
bool hasIncompleteVerificationFeedback(List<ChecklistItem> feedback) {
  return feedback.any((item) => !item.completed);
}

/// 新增了验证反馈且当前不在待返工列时，返回应移入的列 id；否则 `null`。
String? targetReworkColumnIdIfNeeded({
  required List<ChecklistItem> originalFeedback,
  required List<ChecklistItem> nextFeedback,
  required String currentColumnId,
  required Iterable<KanbanColumn> columns,
}) {
  if (!hasAddedVerificationFeedbackItems(
    original: originalFeedback,
    next: nextFeedback,
  )) {
    return null;
  }
  final rework = findReworkColumn(columns);
  if (rework == null || rework.id == currentColumnId) return null;
  return rework.id;
}

/// 存在未完成验证反馈且当前不在待返工列时，返回应移入的列 id；否则 `null`。
///
/// 用于「完成」操作：待返工优先于移入已完成。
String? targetReworkColumnIdIfIncompleteFeedback({
  required List<ChecklistItem> feedback,
  required String currentColumnId,
  required Iterable<KanbanColumn> columns,
}) {
  if (!hasIncompleteVerificationFeedback(feedback)) return null;
  final rework = findReworkColumn(columns);
  if (rework == null || rework.id == currentColumnId) return null;
  return rework.id;
}

/// 点「完成」时是否应优先落「待返工」而非「已完成」。
///
/// 只要当前仍有未完成验证反馈（含本次新增），就不走已完成迁移。
bool shouldPreferReworkOverComplete({
  required List<ChecklistItem> nextFeedback,
}) {
  return hasIncompleteVerificationFeedback(nextFeedback);
}
