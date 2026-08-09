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

const _weekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String _weekdayLabel(int weekday) => _weekdayLabels[weekday - DateTime.monday];

String _hhmm(DateTime local) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// 智能紧凑本地日期时间（一律含周几）。
///
/// - 今天：`HH:mm 周X`
/// - 本月非今天：`D日 周X HH:mm`
/// - 本年非本月：`M月D日 周X HH:mm`
/// - 更早：`YYYY年M月D日 周X HH:mm`
///
/// 无效（≤0）返回 null。[now] 可注入以便测试。
String? formatSmartCompactDateTime(int epochMs, {DateTime? now}) {
  if (epochMs <= 0) return null;
  final local = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  final weekday = _weekdayLabel(local.weekday);
  final time = _hhmm(local);

  final sameDay = local.year == reference.year &&
      local.month == reference.month &&
      local.day == reference.day;
  if (sameDay) {
    return '$time $weekday';
  }

  final sameMonth =
      local.year == reference.year && local.month == reference.month;
  if (sameMonth) {
    return '${local.day}日 $weekday $time';
  }

  if (local.year == reference.year) {
    return '${local.month}月${local.day}日 $weekday $time';
  }

  return '${local.year}年${local.month}月${local.day}日 $weekday $time';
}

/// 卡片详情只读时间元信息（简体中文）。全无效时返回 null。
String? formatCardDetailTimestamps({
  required int createdAt,
  required int updatedAt,
  int? completedAt,
  DateTime? now,
}) {
  final parts = <String>[];
  final created = formatSmartCompactDateTime(createdAt, now: now);
  if (created != null) parts.add('创建于 $created');
  final updated = formatSmartCompactDateTime(updatedAt, now: now);
  if (updated != null) parts.add('更新于 $updated');
  if (completedAt != null) {
    final done = formatSmartCompactDateTime(completedAt, now: now);
    if (done != null) parts.add('完成于 $done');
  }
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}
