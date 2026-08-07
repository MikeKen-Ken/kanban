import '../../models/kanban_models.dart';

/// 保留天数预设：`0` 表示从不自动清空。
const List<int> completedAutoClearDayOptions = [0, 1, 3, 7, 14, 30, 90];

/// 两次自动清空扫描的最短间隔，避免前后台频繁切换时反复扫盘。
const Duration completedAutoClearMinInterval = Duration(hours: 1);

/// 设置项展示文案。
String completedAutoClearDaysLabel(int days) {
  if (days <= 0) return '从不';
  return '$days 天';
}

/// 用于判断「完成多久」的时间戳：优先 [KanbanCard.completedAt]，否则 [KanbanCard.updatedAt]。
int completedReferenceMs(KanbanCard card) => card.completedAt ?? card.updatedAt;

/// 在看板中定位已完成列（与看板控制器识别规则一致）。
KanbanColumn? findDoneColumn(
  KanbanBoard board, {
  required String doneColumnName,
}) {
  for (final col in board.columns) {
    if (col.id == 'done') return col;
  }
  for (final col in board.columns) {
    if (col.title == doneColumnName) return col;
  }
  for (final col in board.columns) {
    if (col.title.contains('完成')) return col;
  }
  return null;
}

/// 筛选已完成列中超过保留天数的卡片。
///
/// [retainDays] ≤ 0 时返回空列表（表示禁用自动清空）。
List<KanbanCard> selectExpiredCompletedCards({
  required KanbanBoard board,
  required String doneColumnName,
  required int retainDays,
  required DateTime now,
}) {
  if (retainDays <= 0) return const [];
  final done = findDoneColumn(board, doneColumnName: doneColumnName);
  if (done == null || done.cards.isEmpty) return const [];

  final cutoffMs =
      now.subtract(Duration(days: retainDays)).millisecondsSinceEpoch;
  return [
    for (final card in done.cards)
      if (completedReferenceMs(card) < cutoffMs) card,
  ];
}
