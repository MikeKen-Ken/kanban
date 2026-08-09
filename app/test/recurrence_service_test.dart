import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/reminders/recurrence_service.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  const service = RecurrenceService();

  test('每月重复会把月末日期钳制到目标月最后一天', () {
    final current = DateTime(2026, 1, 31, 9, 30);
    final next = service.nextDate(current, CardRecurrence.monthly);

    expect(next, DateTime(2026, 2, 28, 9, 30));
  });

  test('间隔大于 1 时按步长推进日/周/月', () {
    final day = DateTime(2026, 8, 1, 10);
    expect(
      service.nextDate(day, CardRecurrence.daily, interval: 3),
      DateTime(2026, 8, 4, 10),
    );
    expect(
      service.nextDate(day, CardRecurrence.weekly, interval: 2),
      DateTime(2026, 8, 15, 10),
    );
    expect(
      service.nextDate(DateTime(2026, 1, 31, 9), CardRecurrence.monthly,
          interval: 2),
      DateTime(2026, 3, 31, 9),
    );
  });

  test('非法间隔按 1 处理', () {
    final current = DateTime(2026, 8, 1);
    expect(
      service.nextDate(current, CardRecurrence.daily, interval: 0),
      DateTime(2026, 8, 2),
    );
  });

  test('下一期使用稳定系列和周期标识并重置完成状态', () {
    final due = DateTime(2026, 8, 3, 18).millisecondsSinceEpoch;
    final reminder = DateTime(2026, 8, 3, 17).millisecondsSinceEpoch;
    final card = KanbanCard(
      id: 'card-1',
      title: '周报',
      order: 2,
      createdAt: 1,
      completed: true,
      completedAt: 2,
      dueDate: due,
      reminderAt: reminder,
      recurrence: CardRecurrence.weekly,
      checklist: [
        ChecklistItem(id: 'item-1', text: '整理数据', completed: true),
      ],
    );

    final next = service.createNextOccurrence(card)!;
    final nextDue = DateTime(2026, 8, 10, 18).millisecondsSinceEpoch;

    expect(next.id, 'rec-card-1-$nextDue');
    expect(next.recurrenceSeriesId, 'card-1');
    expect(next.recurrenceInterval, 1);
    expect(next.completed, isFalse);
    expect(next.completedAt, isNull);
    expect(next.dueDate, nextDue);
    expect(next.reminderAt, nextDue - const Duration(hours: 1).inMilliseconds);
    expect(next.checklist.single.completed, isFalse);
  });

  test('下一期继承间隔并按间隔推算截止日期', () {
    final due = DateTime(2026, 8, 3, 18).millisecondsSinceEpoch;
    final card = KanbanCard(
      id: 'card-1',
      title: '双周报',
      order: 0,
      createdAt: 1,
      dueDate: due,
      recurrence: CardRecurrence.weekly,
      recurrenceInterval: 2,
    );

    final next = service.createNextOccurrence(card)!;
    final nextDue = DateTime(2026, 8, 17, 18).millisecondsSinceEpoch;
    expect(next.dueDate, nextDue);
    expect(next.recurrenceInterval, 2);
  });

  test('无截止日期或不重复时不会生成下一期', () {
    final card = KanbanCard(
      id: 'card-1',
      title: '普通任务',
      order: 0,
      createdAt: 1,
    );

    expect(service.createNextOccurrence(card), isNull);
  });

  test('旧 JSON 缺 recurrenceInterval 时默认为 1，且默认不写出', () {
    final restored = KanbanCard.fromJson({
      'id': 'c1',
      'title': '任务',
      'order': 0,
      'createdAt': 1,
      'recurrence': 'daily',
    });
    expect(restored.recurrence, CardRecurrence.daily);
    expect(restored.recurrenceInterval, 1);
    expect(restored.toJson().containsKey('recurrenceInterval'), isFalse);

    final withInterval = restored.copyWith(recurrenceInterval: 3);
    expect(withInterval.toJson()['recurrenceInterval'], 3);
  });

  test('菜单顺序为每天、每周、每月、不重复', () {
    expect(CardRecurrence.menuOrder, [
      CardRecurrence.daily,
      CardRecurrence.weekly,
      CardRecurrence.monthly,
      CardRecurrence.none,
    ]);
  });
}
