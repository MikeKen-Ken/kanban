import '../project/project_settings.dart';
import '../../models/kanban_models.dart';
import '../completed_auto_clear/completed_auto_clear.dart';

/// 跨项目转移时默认落点列 id。
const kDefaultTransferColumnId = 'todo';

/// 解析卡片转移到目标看板时应落入的列。
///
/// 优先 [preferredColumnId]（默认 `todo`）；若无该列则取第一个非「已完成」列；
/// 再不行则取按 order 排序后的第一列。
String? resolveTransferTargetColumnId(
  KanbanBoard board, {
  String preferredColumnId = kDefaultTransferColumnId,
  String doneColumnName = ProjectSettings.defaultDoneColumnName,
}) {
  final columns = [...board.columns]..sort((a, b) => a.order.compareTo(b.order));
  if (columns.isEmpty) return null;

  for (final col in columns) {
    if (col.id == preferredColumnId) return col.id;
  }

  final done = findDoneColumn(board, doneColumnName: doneColumnName);
  final doneId = done?.id;
  for (final col in columns) {
    if (col.id != doneId) return col.id;
  }
  return columns.first.id;
}
