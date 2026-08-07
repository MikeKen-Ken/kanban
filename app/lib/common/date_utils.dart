/// 返回 [value] 所在本地日期的零点。
DateTime startOfLocalDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// 返回 [value] 所在本地周的周一零点。
DateTime startOfLocalWeek(DateTime value) {
  final day = startOfLocalDay(value);
  return DateTime(
    day.year,
    day.month,
    day.day - (day.weekday - DateTime.monday),
  );
}

/// 判断毫秒时间戳是否落在 [now] 的本地自然日内。
bool isDueToday(int timestamp, DateTime now) {
  final start = startOfLocalDay(now);
  final end = DateTime(start.year, start.month, start.day + 1);
  final value = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return !value.isBefore(start) && value.isBefore(end);
}

/// 判断毫秒时间戳是否早于 [now] 的本地自然日。
bool isOverdue(int timestamp, DateTime now) {
  final value = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return value.isBefore(startOfLocalDay(now));
}

/// 判断毫秒时间戳是否落在 [now] 的本地周（周一至下周一）内。
bool isDueThisWeek(int timestamp, DateTime now) {
  final start = startOfLocalWeek(now);
  final end = DateTime(start.year, start.month, start.day + 7);
  final value = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return !value.isBefore(start) && value.isBefore(end);
}

/// 将毫秒 epoch 格式化为本地 `yyyy-MM-dd HH:mm`；无效（≤0）返回 null。
String? formatEpochMsAsLocalDateTime(int epochMs) {
  if (epochMs <= 0) return null;
  final local = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// 卡片详情只读时间元信息（简体中文）。全无效时返回 null。
String? formatCardDetailTimestamps({
  required int createdAt,
  required int updatedAt,
  int? completedAt,
}) {
  final parts = <String>[];
  final created = formatEpochMsAsLocalDateTime(createdAt);
  if (created != null) parts.add('创建于 $created');
  final updated = formatEpochMsAsLocalDateTime(updatedAt);
  if (updated != null) parts.add('更新于 $updated');
  if (completedAt != null) {
    final done = formatEpochMsAsLocalDateTime(completedAt);
    if (done != null) parts.add('完成于 $done');
  }
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}
