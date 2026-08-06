import '../../common/date_utils.dart';

/// 截止日期快捷预设。
///
/// 全部返回**本地自然日零点**（与 [showDatePicker] 选中结果一致，不含具体时分）。
///
/// 语义约定：
/// - [today]：今天
/// - [tomorrow]：明天
/// - [thisWeek]：**本周日**（一周从周一开始，与 [startOfLocalWeek] 一致；
///   若今天已是周日则为今天）
/// - [inTwoWeeks]：今天起第 14 天（即「两周后」的同一星期几）
/// - [thisMonth]：**本月最后一天**
enum DueDateShortcut {
  today,
  tomorrow,
  thisWeek,
  inTwoWeeks,
  thisMonth;

  String get label => switch (this) {
        DueDateShortcut.today => '今天',
        DueDateShortcut.tomorrow => '明天',
        DueDateShortcut.thisWeek => '本周',
        DueDateShortcut.inTwoWeeks => '两周',
        DueDateShortcut.thisMonth => '本月',
      };

  /// 根据 [now] 解析该快捷对应的截止日期（本地零点）。
  DateTime resolve(DateTime now) {
    final today = startOfLocalDay(now);
    return switch (this) {
      DueDateShortcut.today => today,
      DueDateShortcut.tomorrow =>
        DateTime(today.year, today.month, today.day + 1),
      DueDateShortcut.thisWeek => endOfLocalWeek(today),
      DueDateShortcut.inTwoWeeks =>
        DateTime(today.year, today.month, today.day + 14),
      DueDateShortcut.thisMonth => endOfLocalMonth(today),
    };
  }
}

/// 返回 [value] 所在本地周的周日零点（周一起始）。
DateTime endOfLocalWeek(DateTime value) {
  final start = startOfLocalWeek(value);
  return DateTime(start.year, start.month, start.day + 6);
}

/// 返回 [value] 所在本地月的最后一天零点。
DateTime endOfLocalMonth(DateTime value) {
  final day = startOfLocalDay(value);
  return DateTime(day.year, day.month + 1, 0);
}

/// 判断两个日期是否为同一本地自然日。
bool isSameLocalDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  final left = startOfLocalDay(a);
  final right = startOfLocalDay(b);
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
