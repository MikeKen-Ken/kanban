import '../project/project_settings.dart';
import '../../models/kanban_models.dart';
import '../completed_auto_clear/completed_auto_clear.dart';

/// 跨项目转移时默认落点列 id。
const kDefaultTransferColumnId = 'todo';

/// 默认「待办」列标题（与 [KanbanBoard.empty] 一致）。
const kDefaultTransferColumnTitle = 'To Do';

/// 解析卡片转移到目标看板时应落入的列。
///
/// 优先级：
/// 1. 目标板中与 [sourceColumnTitle]（trim 后）标题精确匹配的列；
/// 2. [preferredColumnId]（默认 `todo`），或标题为「待办」的列；
/// 3. 第一个非「已完成」列；
/// 4. 按 order 排序后的第一列。
String? resolveTransferTargetColumnId(
  KanbanBoard board, {
  String? sourceColumnTitle,
  String preferredColumnId = kDefaultTransferColumnId,
  String preferredColumnTitle = kDefaultTransferColumnTitle,
  String doneColumnName = ProjectSettings.defaultDoneColumnName,
}) {
  final columns = [...board.columns]
    ..sort((a, b) => a.order.compareTo(b.order));
  if (columns.isEmpty) return null;

  final sourceTitle = sourceColumnTitle?.trim();
  if (sourceTitle != null && sourceTitle.isNotEmpty) {
    for (final col in columns) {
      if (col.title.trim() == sourceTitle) return col.id;
    }
  }

  final preferredTitle = preferredColumnTitle.trim();
  for (final col in columns) {
    if (col.id == preferredColumnId) return col.id;
  }
  if (preferredTitle.isNotEmpty) {
    for (final col in columns) {
      if (col.title.trim() == preferredTitle) return col.id;
    }
  }

  final done = findDoneColumn(board, doneColumnName: doneColumnName);
  final doneId = done?.id;
  for (final col in columns) {
    if (col.id != doneId) return col.id;
  }
  return columns.first.id;
}
