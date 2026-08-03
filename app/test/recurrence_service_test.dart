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
    expect(next.completed, isFalse);
    expect(next.completedAt, isNull);
    expect(next.dueDate, nextDue);
    expect(next.reminderAt, nextDue - const Duration(hours: 1).inMilliseconds);
    expect(next.checklist.single.completed, isFalse);
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
}
