import '../../models/kanban_models.dart';

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

/// 待验证列打开详情时，备注应默认进入 Markdown 预览。
bool shouldDefaultPreviewMarkdown({
  required String columnId,
  required Iterable<KanbanColumn> columns,
}) {
  return isVerifyColumnId(columnId: columnId, columns: columns);
}
