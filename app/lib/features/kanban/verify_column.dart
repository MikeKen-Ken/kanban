import '../../models/kanban_models.dart';
import '../completed_auto_clear/completed_auto_clear.dart';
import 'move_to_rework_on_new_feedback.dart';

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

/// [columnId] 是否对应看板中的「阻塞中」列。
///
/// 阻塞列在已有看板中可能使用 UUID，按标题识别后再回退默认 id。
bool isBlockedColumnId({
  required String columnId,
  required Iterable<KanbanColumn> columns,
}) {
  for (final col in columns) {
    if (col.id != columnId) continue;
    return col.title == '阻塞中' || col.id == 'blocked';
  }
  // 列尚未出现在快照时，仍按默认 id 识别。
  return columnId == 'blocked';
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
  if (columnId == 'doing') return true;
  if (isBlockedColumnId(columnId: columnId, columns: columns)) return true;
  return isDoneColumnId(
    columnId: columnId,
    columns: columns,
    doneColumnName: doneColumnName,
  );
}
