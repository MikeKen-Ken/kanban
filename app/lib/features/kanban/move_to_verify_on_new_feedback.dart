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

/// 解析「待验证」列：标题优先，其次默认 id `verify`。
KanbanColumn? findVerifyColumn(Iterable<KanbanColumn> columns) {
  for (final col in columns) {
    if (col.title == KanbanBoard.defaultVerifyColumnTitle ||
        col.id == 'verify') {
      return col;
    }
  }
  return null;
}

/// 新增了验证反馈且当前不在待验证列时，返回应移入的列 id；否则 `null`。
String? targetVerifyColumnIdIfNeeded({
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
  final verify = findVerifyColumn(columns);
  if (verify == null || verify.id == currentColumnId) return null;
  return verify.id;
}
