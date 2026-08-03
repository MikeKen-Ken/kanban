import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/quick_capture/quick_capture.dart';

void main() {
  group('parseQuickCapture', () {
    final referenceTime = DateTime(2026, 8, 3, 23, 45);

    test('解析带空格的中文标题和全部指令', () {
      final draft = parseQuickCapture(
        '整理 中文 项目资料 #工作 #重要 !高 @进行中 明天',
        now: referenceTime,
      );

      expect(draft.title, '整理 中文 项目资料');
      expect(draft.labels, ['工作', '重要']);
      expect(draft.priority, QuickCapturePriority.high);
      expect(draft.columnName, '进行中');
      expect(draft.dueDate, DateTime(2026, 8, 4));
    });

    test('支持今天、明天、后天和下周的本地自然日', () {
      final cases = <String, DateTime>{
        '今天': DateTime(2026, 8, 3),
        '明天': DateTime(2026, 8, 4),
        '后天': DateTime(2026, 8, 5),
        '下周': DateTime(2026, 8, 10),
      };

      for (final entry in cases.entries) {
        final draft = parseQuickCapture(
          '任务 ${entry.key}',
          now: referenceTime,
        );

        expect(draft.dueDate, entry.value, reason: entry.key);
      }
    });

    test('跨月计算自然日', () {
      final draft = parseQuickCapture(
        '月底任务 后天',
        now: DateTime(2026, 8, 31, 22),
      );

      expect(draft.dueDate, DateTime(2026, 9, 2));
    });

    test('解析三种优先级', () {
      expect(
        parseQuickCapture('任务 !低').priority,
        QuickCapturePriority.low,
      );
      expect(
        parseQuickCapture('任务 !中').priority,
        QuickCapturePriority.medium,
      );
      expect(
        parseQuickCapture('任务 !高').priority,
        QuickCapturePriority.high,
      );
    });

    test('无法识别和缺少内容的指令保留为标题', () {
      final draft = parseQuickCapture(
        '处理 !紧急 # @ 昨天 @待确认事项?',
        now: referenceTime,
      );

      expect(draft.title, '处理 !紧急 # @ 昨天');
      expect(draft.columnName, '待确认事项?');
      expect(draft.labels, isEmpty);
      expect(draft.priority, isNull);
      expect(draft.dueDate, isNull);
    });

    test('仅识别由空白分隔的完整指令', () {
      final draft = parseQuickCapture(
        '说明今天完成 邮件@收件箱 标题#备注',
        now: referenceTime,
      );

      expect(draft.title, '说明今天完成 邮件@收件箱 标题#备注');
      expect(draft.columnName, isNull);
      expect(draft.labels, isEmpty);
      expect(draft.dueDate, isNull);
    });

    test('标签按输入顺序去重', () {
      final draft = parseQuickCapture('任务 #工作 #生活 #工作');

      expect(draft.labels, ['工作', '生活']);
    });

    test('重复的单值指令采用最后一个有效值', () {
      final draft = parseQuickCapture(
        '任务 !低 !高 @待办 @处理中 今天 后天',
        now: referenceTime,
      );

      expect(draft.priority, QuickCapturePriority.high);
      expect(draft.columnName, '处理中');
      expect(draft.dueDate, DateTime(2026, 8, 5));
    });

    test('空白输入返回空草稿', () {
      final draft = parseQuickCapture(' \t\n ');

      expect(draft.title, isEmpty);
      expect(draft.labels, isEmpty);
      expect(draft.priority, isNull);
      expect(draft.columnName, isNull);
      expect(draft.dueDate, isNull);
    });
  });
}
