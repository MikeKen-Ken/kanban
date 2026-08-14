/// 自动备份保留天数预设：`0` 表示从不自动清理。
const List<int> autoBackupRetentionDayOptions = [0, 7, 14, 30, 90];

/// 设置项展示文案。
String autoBackupRetentionDaysLabel(int days) {
  if (days <= 0) return '从不';
  return '$days 天';
}
