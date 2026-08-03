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
