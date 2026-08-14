import '../../models/kanban_models.dart';

/// 在给定列集合中统计已完成的前置依赖数量；找不到的卡视为未完成。
int countCompletedBlockedBy({
  required List<String> blockedByIds,
  required List<KanbanColumn> columns,
}) {
  if (blockedByIds.isEmpty) return 0;
  final byId = <String, KanbanCard>{};
  for (final column in columns) {
    for (final card in column.cards) {
      byId[card.id] = card;
    }
  }
  var done = 0;
  for (final id in blockedByIds) {
    if (byId[id]?.completed == true) done++;
  }
  return done;
}
