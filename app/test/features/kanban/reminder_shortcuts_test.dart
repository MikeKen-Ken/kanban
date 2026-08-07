import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/reminder_shortcuts.dart';

void main() {
  // 2026-08-05 为周三 15:30
  final wednesdayAfternoon = DateTime(2026, 8, 5, 15, 30);
  // 周三晚上已过 18:00
  final wednesdayNight = DateTime(2026, 8, 5, 19, 10);
  // 2026-08-08 为周六上午早于 09:00
  final saturdayEarly = DateTime(2026, 8, 8, 8, 0);
  // 周六已过 09:00
  final saturdayLate = DateTime(2026, 8, 8, 10, 0);
  // 周日
  final sunday = DateTime(2026, 8, 9, 12, 0);
  // 周一上午
  final monday = DateTime(2026, 8, 10, 9, 0);

  test('稍后为当前起 1 小时（去秒）', () {
    expect(
      ReminderShortcut.later.resolve(wednesdayAfternoon),
      DateTime(2026, 8, 5, 16, 30),
    );
    expect(
      ReminderShortcut.later.resolve(DateTime(2026, 8, 5, 23, 45, 59)),
      DateTime(2026, 8, 6, 0, 45),
    );
  });

  test('今晚为当天 18:00；已过则次日 18:00', () {
    expect(
      ReminderShortcut.tonight.resolve(wednesdayAfternoon),
      DateTime(2026, 8, 5, 18),
    );
    expect(
      ReminderShortcut.tonight.resolve(wednesdayNight),
      DateTime(2026, 8, 6, 18),
    );
  });

  test('明天上午/下午为次日 09:00 与 15:00', () {
    expect(
      ReminderShortcut.tomorrowMorning.resolve(wednesdayAfternoon),
      DateTime(2026, 8, 6, 9),
    );
    expect(
      ReminderShortcut.tomorrowAfternoon.resolve(wednesdayAfternoon),
      DateTime(2026, 8, 6, 15),
    );
  });

  test('周末为即将到来的周六 09:00', () {
    expect(
      ReminderShortcut.thisWeekend.resolve(wednesdayAfternoon),
      DateTime(2026, 8, 8, 9),
    );
    expect(
      ReminderShortcut.thisWeekend.resolve(saturdayEarly),
      DateTime(2026, 8, 8, 9),
    );
    expect(
      ReminderShortcut.thisWeekend.resolve(saturdayLate),
      DateTime(2026, 8, 15, 9),
    );
    expect(
      ReminderShortcut.thisWeekend.resolve(sunday),
      DateTime(2026, 8, 15, 9),
    );
  });

  test('下周为下周一 09:00', () {
    expect(
      ReminderShortcut.nextWeek.resolve(wednesdayAfternoon),
      DateTime(2026, 8, 10, 9),
    );
    expect(
      ReminderShortcut.nextWeek.resolve(monday),
      DateTime(2026, 8, 17, 9),
    );
  });

  test('isSameLocalMinute 精确到分钟', () {
    expect(
      isSameLocalMinute(
        DateTime(2026, 8, 5, 18, 0, 30),
        DateTime(2026, 8, 5, 18, 0, 1),
      ),
      isTrue,
    );
    expect(
      isSameLocalMinute(
        DateTime(2026, 8, 5, 18, 0),
        DateTime(2026, 8, 5, 18, 1),
      ),
      isFalse,
    );
    expect(isSameLocalMinute(null, DateTime(2026, 8, 5, 18)), isFalse);
  });
}
