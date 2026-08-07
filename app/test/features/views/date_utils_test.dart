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

  test('epoch 格式化为本地 yyyy-MM-dd HH:mm；无效值返回 null', () {
    expect(formatEpochMsAsLocalDateTime(0), isNull);
    expect(formatEpochMsAsLocalDateTime(-1), isNull);

    final epoch = DateTime(2026, 8, 7, 15, 8).millisecondsSinceEpoch;
    expect(formatEpochMsAsLocalDateTime(epoch), '2026-08-07 15:08');
  });

  test('卡片详情时间元信息行：创建/更新必显，完成可选', () {
    final created = DateTime(2026, 1, 2, 3, 4).millisecondsSinceEpoch;
    final updated = DateTime(2026, 8, 7, 15, 30).millisecondsSinceEpoch;
    final completed = DateTime(2026, 8, 6, 10, 0).millisecondsSinceEpoch;

    expect(
      formatCardDetailTimestamps(createdAt: created, updatedAt: updated),
      '创建于 2026-01-02 03:04 · 更新于 2026-08-07 15:30',
    );
    expect(
      formatCardDetailTimestamps(
        createdAt: created,
        updatedAt: updated,
        completedAt: completed,
      ),
      '创建于 2026-01-02 03:04 · 更新于 2026-08-07 15:30 · 完成于 2026-08-06 10:00',
    );
    expect(
      formatCardDetailTimestamps(createdAt: 0, updatedAt: 0),
      isNull,
    );
  });
}
