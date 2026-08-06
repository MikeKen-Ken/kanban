import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/due_date_shortcuts.dart';

void main() {
  // 2026-08-05 为周三
  final wednesday = DateTime(2026, 8, 5, 15, 30);
  // 2026-08-09 为周日
  final sunday = DateTime(2026, 8, 9, 10);
  // 月末
  final endOfAugustDay = DateTime(2026, 8, 31, 8);

  test('今天/明天为本地自然日零点', () {
    expect(
      DueDateShortcut.today.resolve(wednesday),
      DateTime(2026, 8, 5),
    );
    expect(
      DueDateShortcut.tomorrow.resolve(wednesday),
      DateTime(2026, 8, 6),
    );
  });

  test('本周为本周日；若已是周日则为当天', () {
    expect(
      DueDateShortcut.thisWeek.resolve(wednesday),
      DateTime(2026, 8, 9),
    );
    expect(
      DueDateShortcut.thisWeek.resolve(sunday),
      DateTime(2026, 8, 9),
    );
  });

  test('两周为今天起第 14 天', () {
    expect(
      DueDateShortcut.inTwoWeeks.resolve(wednesday),
      DateTime(2026, 8, 19),
    );
  });

  test('本月为本月最后一天', () {
    expect(
      DueDateShortcut.thisMonth.resolve(wednesday),
      DateTime(2026, 8, 31),
    );
    expect(
      DueDateShortcut.thisMonth.resolve(endOfAugustDay),
      DateTime(2026, 8, 31),
    );
  });

  test('isSameLocalDay 忽略时分', () {
    expect(
      isSameLocalDay(
        DateTime(2026, 8, 5, 1),
        DateTime(2026, 8, 5, 23),
      ),
      isTrue,
    );
    expect(
      isSameLocalDay(DateTime(2026, 8, 5), DateTime(2026, 8, 6)),
      isFalse,
    );
    expect(isSameLocalDay(null, DateTime(2026, 8, 5)), isFalse);
  });
}
