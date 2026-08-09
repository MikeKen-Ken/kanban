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

  group('formatSmartCompactDateTime', () {
    // 2026-08-05 是周三
    final reference = DateTime(2026, 8, 5, 18, 0);

    test('无效时间戳返回 null', () {
      expect(formatSmartCompactDateTime(0, now: reference), isNull);
      expect(formatSmartCompactDateTime(-1, now: reference), isNull);
    });

    test('今天：仅时间 + 周几', () {
      final epoch = DateTime(2026, 8, 5, 9, 5).millisecondsSinceEpoch;
      expect(
        formatSmartCompactDateTime(epoch, now: reference),
        '09:05 周三',
      );
    });

    test('本月非今天：日 + 周几 + 时间', () {
      // 2026-08-01 是周六
      final epoch = DateTime(2026, 8, 1, 14, 30).millisecondsSinceEpoch;
      expect(
        formatSmartCompactDateTime(epoch, now: reference),
        '1日 周六 14:30',
      );
    });

    test('本年非本月：月日 + 周几 + 时间', () {
      // 2026-01-02 是周五
      final epoch = DateTime(2026, 1, 2, 3, 4).millisecondsSinceEpoch;
      expect(
        formatSmartCompactDateTime(epoch, now: reference),
        '1月2日 周五 03:04',
      );
    });

    test('更早：年月日 + 周几 + 时间', () {
      // 2025-12-01 是周一
      final epoch = DateTime(2025, 12, 1, 10, 0).millisecondsSinceEpoch;
      expect(
        formatSmartCompactDateTime(epoch, now: reference),
        '2025年12月1日 周一 10:00',
      );
    });
  });

  test('卡片详情时间元信息行：创建/更新必显，完成可选', () {
    final reference = DateTime(2026, 8, 9, 12, 0);
    final created = DateTime(2026, 1, 2, 3, 4).millisecondsSinceEpoch;
    final updated = DateTime(2026, 8, 7, 15, 30).millisecondsSinceEpoch;
    final completed = DateTime(2026, 8, 6, 10, 0).millisecondsSinceEpoch;

    expect(
      formatCardDetailTimestamps(
        createdAt: created,
        updatedAt: updated,
        now: reference,
      ),
      '创建于 1月2日 周五 03:04 · 更新于 7日 周五 15:30',
    );
    expect(
      formatCardDetailTimestamps(
        createdAt: created,
        updatedAt: updated,
        completedAt: completed,
        now: reference,
      ),
      '创建于 1月2日 周五 03:04 · 更新于 7日 周五 15:30 · 完成于 6日 周四 10:00',
    );
    expect(
      formatCardDetailTimestamps(createdAt: 0, updatedAt: 0, now: reference),
      isNull,
    );
  });
}
