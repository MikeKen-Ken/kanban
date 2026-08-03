import '../../models/kanban_models.dart';

/// 负责重复任务的日期计算与幂等下一期生成，不包含平台通知逻辑。
class RecurrenceService {
  const RecurrenceService();

  DateTime? nextDate(DateTime current, CardRecurrence recurrence) {
    return switch (recurrence) {
      CardRecurrence.none => null,
      CardRecurrence.daily => DateTime(
          current.year,
          current.month,
          current.day + 1,
          current.hour,
          current.minute,
        ),
      CardRecurrence.weekly => DateTime(
          current.year,
          current.month,
          current.day + 7,
          current.hour,
          current.minute,
        ),
      CardRecurrence.monthly => _nextMonth(current),
    };
  }

  KanbanCard? createNextOccurrence(KanbanCard completedCard) {
    final dueAt = completedCard.dueDate;
    if (dueAt == null || completedCard.recurrence == CardRecurrence.none) {
      return null;
    }

    final currentDue = DateTime.fromMillisecondsSinceEpoch(dueAt);
    final nextDue = nextDate(currentDue, completedCard.recurrence);
    if (nextDue == null) return null;

    final seriesId = completedCard.recurrenceSeriesId ?? completedCard.id;
    final nextDueAt = nextDue.millisecondsSinceEpoch;
    final reminderOffset = completedCard.reminderAt == null
        ? null
        : dueAt - completedCard.reminderAt!;

    return KanbanCard(
      id: 'rec-$seriesId-$nextDueAt',
      title: completedCard.title,
      description: completedCard.description,
      order: completedCard.order,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      completed: false,
      dueDate: nextDueAt,
      reminderAt: reminderOffset == null ? null : nextDueAt - reminderOffset,
      recurrence: completedCard.recurrence,
      recurrenceSeriesId: seriesId,
      priority: completedCard.priority,
      labels: [...completedCard.labels],
      checklist: [
        for (final item in completedCard.checklist)
          item.copyWith(completed: false),
      ],
      colorValue: completedCard.colorValue,
    );
  }

  DateTime _nextMonth(DateTime current) {
    final firstOfTarget = DateTime(
      current.year,
      current.month + 1,
      1,
      current.hour,
      current.minute,
    );
    final lastDay = DateTime(
      firstOfTarget.year,
      firstOfTarget.month + 1,
      0,
    ).day;
    return DateTime(
      firstOfTarget.year,
      firstOfTarget.month,
      current.day > lastDay ? lastDay : current.day,
      current.hour,
      current.minute,
    );
  }
}
