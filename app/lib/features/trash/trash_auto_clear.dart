import 'trash_models.dart';

/// 回收站保留天数预设：`0` 表示从不自动清理。
const List<int> trashRetentionDayOptions = [0, 7, 30, 90];

/// 两次回收站自动清理的最短间隔，避免前后台频繁切换时反复扫盘。
const Duration trashAutoClearMinInterval = Duration(hours: 1);

/// 设置项展示文案。
String trashRetentionDaysLabel(int days) {
  if (days <= 0) return 'Never';
  if (days == 1) return '1 day';
  return '$days days';
}

/// 筛选超过保留天数的回收项。
///
/// [retainDays] ≤ 0 时返回空列表（表示禁用自动清理）。
List<TrashItem> selectExpiredTrashItems({
  required Iterable<TrashItem> items,
  required int retainDays,
  required DateTime now,
}) {
  if (retainDays <= 0) return const [];
  final cutoffMs =
      now.subtract(Duration(days: retainDays)).millisecondsSinceEpoch;
  return [
    for (final item in items)
      if (item.deletedAt < cutoffMs) item,
  ];
}
