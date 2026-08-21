import '../completed_auto_clear/completed_auto_clear.dart';
import '../../models/kanban_models.dart';
import '../project/project_settings.dart';

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
  final list =
      columns is List<KanbanColumn> ? columns : List<KanbanColumn>.of(columns);
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

/// 没有未完成验证反馈时禁止移入「待返工」的提示文案。
const reworkMoveRequiresFeedbackMessage =
    'Add incomplete feedback before moving to rework';

/// 仍有验证反馈未完成时，卡片不能移入已完成列或被标记完成。
const incompleteVerificationFeedbackBlocksProgressMessage =
    'Complete all verification feedback before moving to Done or marking complete';

/// 待返工列仍有未完成验证反馈时，不可移入其他列（「进行中」「阻塞中」除外）。
const incompleteVerificationFeedbackBlocksReworkExitMessage =
    'Complete all verification feedback before leaving the Rework column';

/// 默认「进行中」列标题（与 [KanbanBoard.empty] 一致）。
const _defaultDoingColumnTitle = 'In Progress';

/// 默认「进行中」列 id。
const _defaultDoingColumnId = 'doing';

/// 默认「阻塞中」列标题。
const _defaultBlockedColumnTitle = 'Blocked';

/// 默认「阻塞中」列 id。
const _defaultBlockedColumnId = 'blocked';

/// 待返工卡实施中允许落入的列：进行中（继续实施）或阻塞中（无法继续）。
bool isReworkActiveWorkColumnId({
  required String columnId,
  required Iterable<KanbanColumn> columns,
}) {
  for (final col in columns) {
    if (col.id != columnId) continue;
    return col.title == _defaultDoingColumnTitle ||
        col.id == _defaultDoingColumnId ||
        col.title == _defaultBlockedColumnTitle ||
        col.id == _defaultBlockedColumnId;
  }
  return columnId == _defaultDoingColumnId ||
      columnId == _defaultBlockedColumnId;
}

/// 跨列移卡门禁：没有未完成反馈不可入待返工；待返工有未完成反馈时仅可移入
/// 「进行中」或「阻塞中」；有未完成反馈不可入已完成列。
///
/// 同列内重排不校验。仅已完成的反馈不能进入待返工。
/// 已完成列按 [doneColumnName] 识别（项目设置可自定义，默认「已完成」）。
/// 不覆盖「新增反馈后自动移入」：该路径会先写入反馈再调用移卡。
String? reworkMoveRejectionReason({
  required String fromColumnId,
  required String toColumnId,
  required List<ChecklistItem> verificationFeedback,
  required Iterable<KanbanColumn> columns,
  String doneColumnName = ProjectSettings.defaultDoneColumnName,
}) {
  if (fromColumnId == toColumnId) return null;
  if (hasIncompleteVerificationFeedback(verificationFeedback) &&
      isReworkColumnId(columnId: fromColumnId, columns: columns) &&
      !isReworkColumnId(columnId: toColumnId, columns: columns) &&
      !isReworkActiveWorkColumnId(columnId: toColumnId, columns: columns)) {
    return incompleteVerificationFeedbackBlocksReworkExitMessage;
  }
  if (hasIncompleteVerificationFeedback(verificationFeedback) &&
      isDoneColumnId(
        columnId: toColumnId,
        columns: columns,
        doneColumnName: doneColumnName,
      )) {
    return incompleteVerificationFeedbackBlocksProgressMessage;
  }
  if (!isReworkColumnId(columnId: toColumnId, columns: columns)) return null;
  if (hasIncompleteVerificationFeedback(verificationFeedback)) return null;
  return reworkMoveRequiresFeedbackMessage;
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
  if (isReworkActiveWorkColumnId(
    columnId: currentColumnId,
    columns: columns,
  )) {
    return null;
  }
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
