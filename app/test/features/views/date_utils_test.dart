import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/common/date_utils.dart';

void main() {
  final now = DateTime(2026, 8, 5, 15, 30);

  test('自然日边界按本地日期计算', () {
    expect(
      isDueToday(DateTime(2026, 8, 5).millisecondsSinceEpoch, now),
      isTrue,
    );
    expect(
      isDueToday(DateTime(2026, 8, 5, 23, 59).millisecondsSinceEpoch, now),
      isTrue,
    );
    expect(
      isDueToday(DateTime(2026, 8, 6).millisecondsSinceEpoch, now),
      isFalse,
    );
  });

  test('逾期只包含今天零点之前的时间', () {
    expect(
      isOverdue(DateTime(2026, 8, 4, 23, 59).millisecondsSinceEpoch, now),
      isTrue,
    );
    expect(
      isOverdue(DateTime(2026, 8, 5).millisecondsSinceEpoch, now),
      isFalse,
    );
  });

  test('本周使用周一到下周一的半开区间', () {
    expect(startOfLocalWeek(now), DateTime(2026, 8, 3));
    expect(
      isDueThisWeek(DateTime(2026, 8, 3).millisecondsSinceEpoch, now),
      isTrue,
    );
    expect(
      isDueThisWeek(DateTime(2026, 8, 9, 23, 59).millisecondsSinceEpoch, now),
      isTrue,
    );
    expect(
      isDueThisWeek(DateTime(2026, 8, 10).millisecondsSinceEpoch, now),
      isFalse,
    );
  });
}
