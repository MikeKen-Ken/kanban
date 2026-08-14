import '../../models/kanban_models.dart';
import '../completed_auto_clear/completed_auto_clear.dart';
import 'move_to_rework_on_new_feedback.dart';

/// 默认「进行中」列标题（与 [KanbanBoard.empty] 一致）。
const defaultDoingColumnTitle = '进行中';

/// 默认「进行中」列 id。
const defaultDoingColumnId = 'doing';

/// 默认「阻塞中」列标题（与 [KanbanBoard.empty] 一致）。
const defaultBlockedColumnTitle = '阻塞中';

/// 默认「阻塞中」列 id。
const defaultBlockedColumnId = 'blocked';

/// 解析「待验证」列：标题优先，其次默认 id `verify`。
///
/// 自定义列 id（UUID）只要标题为 [KanbanBoard.defaultVerifyColumnTitle] 即可识别。
KanbanColumn? findVerifyColumn(Iterable<KanbanColumn> columns) {
  for (final col in columns) {
    if (col.title == KanbanBoard.defaultVerifyColumnTitle ||
        col.id == 'verify') {
      return col;
    }
  }
  return null;
}

/// 解析「进行中」列：标题优先，再回退默认 id。
KanbanColumn? findDoingColumn(Iterable<KanbanColumn> columns) {
  final list =
      columns is List<KanbanColumn> ? columns : List<KanbanColumn>.of(columns);
  for (final col in list) {
    if (col.title == defaultDoingColumnTitle) return col;
  }
  for (final col in list) {
    if (col.id == defaultDoingColumnId) return col;
  }
  return null;
}

/// 解析「阻塞中」列：标题优先，再回退默认 id。
KanbanColumn? findBlockedColumn(Iterable<KanbanColumn> columns) {
  final list =
      columns is List<KanbanColumn> ? columns : List<KanbanColumn>.of(columns);
  for (final col in list) {
    if (col.title == defaultBlockedColumnTitle) return col;
  }
  for (final col in list) {
    if (col.id == defaultBlockedColumnId) return col;
  }
  return null;
}

/// [columnId] 是否对应看板中的「待验证」列。
bool isVerifyColumnId({
  required String columnId,
  required Iterable<KanbanColumn> columns,
}) {
  for (final col in columns) {
    if (col.id != columnId) continue;
    return col.title == KanbanBoard.defaultVerifyColumnTitle ||
        col.id == 'verify';
  }
  // 列尚未出现在快照时，仍按默认 id 识别。
  return columnId == 'verify';
}

/// [columnId] 是否对应看板中的「进行中」列。
bool isDoingColumnId({
  required String columnId,
  required Iterable<KanbanColumn> columns,
}) {
  for (final col in columns) {
    if (col.id != columnId) continue;
    return col.title == defaultDoingColumnTitle ||
        col.id == defaultDoingColumnId;
  }
  return columnId == defaultDoingColumnId;
}

/// 「进行中」是否有未完成卡（调度当前正在做的那张）。
bool hasIncompleteDoingCard(KanbanBoard board) {
  final doing = findDoingColumn(board.columns);
  if (doing == null) return false;
  for (final card in doing.cards) {
    if (!card.completed) return true;
  }
  return false;
}

/// [columnId] 是否对应看板中的「阻塞中」列。
///
/// 阻塞列在已有看板中可能使用 UUID，按标题识别后再回退默认 id。
bool isBlockedColumnId({
  required String columnId,
  required Iterable<KanbanColumn> columns,
}) {
  for (final col in columns) {
    if (col.id != columnId) continue;
    return col.title == defaultBlockedColumnTitle ||
        col.id == defaultBlockedColumnId;
  }
  // 列尚未出现在快照时，仍按默认 id 识别。
  return columnId == defaultBlockedColumnId;
}

/// 进行中 / 待验证 / 待返工 / 阻塞中 / 已完成打开详情时，备注应默认进入 Markdown 预览。
///
/// 按列角色工具识别，不依赖脆弱的列名硬编码匹配；其他列仍默认编辑。
bool shouldDefaultPreviewMarkdown({
  required String columnId,
  required Iterable<KanbanColumn> columns,
  String doneColumnName = '已完成',
}) {
  if (isVerifyColumnId(columnId: columnId, columns: columns)) return true;
  if (isReworkColumnId(columnId: columnId, columns: columns)) return true;
  if (isDoingColumnId(columnId: columnId, columns: columns)) return true;
  if (isBlockedColumnId(columnId: columnId, columns: columns)) return true;
  return isDoneColumnId(
    columnId: columnId,
    columns: columns,
    doneColumnName: doneColumnName,
  );
}
