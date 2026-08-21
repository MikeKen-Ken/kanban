import '../../common/date_utils.dart';

/// 提醒快捷预设。
///
/// 全部返回**具体本地时分**（写入卡片 `reminderAt`），
/// 参考常见待办/邮件产品的延后与时段约定（如 Gmail/Outlook 延后、
/// Apple Reminders 上午/下午/晚上默认点）：
///
/// - [later]：**稍后** — 当前时刻起 1 小时（去秒）
/// - [tonight]：**今晚** — 当天 18:00；若已过则次日 18:00
/// - [tomorrowMorning]：**明天上午** — 次日 09:00
/// - [tomorrowAfternoon]：**明天下午** — 次日 15:00
/// - [thisWeekend]：**周末** — 即将到来的周六 09:00
///   （本周六 09:00 仍在未来则用之，否则下周六 09:00）
/// - [nextWeek]：**下周** — 下周一 09:00
enum ReminderShortcut {
  later,
  tonight,
  tomorrowMorning,
  tomorrowAfternoon,
  thisWeekend,
  nextWeek;

  String get label => switch (this) {
        ReminderShortcut.later => 'Later',
        ReminderShortcut.tonight => 'Tonight',
        ReminderShortcut.tomorrowMorning => 'Tomorrow morning',
        ReminderShortcut.tomorrowAfternoon => 'Tomorrow afternoon',
        ReminderShortcut.thisWeekend => 'This weekend',
        ReminderShortcut.nextWeek => 'Next week',
      };

  /// 根据 [now] 解析该快捷对应的提醒时刻（本地时区，秒与毫秒为 0）。
  DateTime resolve(DateTime now) {
    final local = now.toLocal();
    final truncated = DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
    return switch (this) {
      ReminderShortcut.later => truncated.add(const Duration(hours: 1)),
      ReminderShortcut.tonight => _tonight(truncated),
      ReminderShortcut.tomorrowMorning => DateTime(
          truncated.year,
          truncated.month,
          truncated.day + 1,
          9,
        ),
      ReminderShortcut.tomorrowAfternoon => DateTime(
          truncated.year,
          truncated.month,
          truncated.day + 1,
          15,
        ),
      ReminderShortcut.thisWeekend => _thisWeekendMorning(truncated),
      ReminderShortcut.nextWeek => _nextMondayMorning(truncated),
    };
  }
}

DateTime _atLocal(DateTime day, int hour, [int minute = 0]) {
  final start = startOfLocalDay(day);
  return DateTime(start.year, start.month, start.day, hour, minute);
}

/// 今晚 18:00；已过则滚到次日 18:00。
DateTime _tonight(DateTime now) {
  final candidate = _atLocal(now, 18);
  if (!candidate.isAfter(now)) {
    return _atLocal(now.add(const Duration(days: 1)), 18);
  }
  return candidate;
}

/// 即将到来的周六 09:00（周一起始周内）。
DateTime _thisWeekendMorning(DateTime now) {
  final today = startOfLocalDay(now);
  final daysUntilSaturday = DateTime.saturday - today.weekday;
  final thisSaturday = DateTime(
    today.year,
    today.month,
    today.day + daysUntilSaturday,
  );
  final candidate = _atLocal(thisSaturday, 9);
  if (candidate.isAfter(now)) return candidate;
  return _atLocal(
    DateTime(thisSaturday.year, thisSaturday.month, thisSaturday.day + 7),
    9,
  );
}

/// 下周一 09:00（严格下一周，即使今天是周一）。
DateTime _nextMondayMorning(DateTime now) {
  final today = startOfLocalDay(now);
  final daysUntilNextMonday = DateTime.monday + 7 - today.weekday;
  return _atLocal(
    DateTime(today.year, today.month, today.day + daysUntilNextMonday),
    9,
  );
}

/// 判断两个时刻是否精确到同一本地分钟（忽略秒与毫秒）。
bool isSameLocalMinute(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day &&
      left.hour == right.hour &&
      left.minute == right.minute;
}
