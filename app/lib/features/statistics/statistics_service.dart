import '../../models/kanban_models.dart';

class KanbanStatistics {
  const KanbanStatistics({
    required this.total,
    required this.completed,
    required this.overdue,
    required this.completedLast7Days,
    required this.averageCompletionHours,
    required this.byProject,
  });

  final int total;
  final int completed;
  final int overdue;
  final List<int> completedLast7Days;
  final double? averageCompletionHours;
  final Map<String, int> byProject;

  int get active => total - completed;
}

class StatisticsService {
  const StatisticsService();

  KanbanStatistics calculate(
    Map<String, KanbanBoard> boards, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final firstDay = today.subtract(const Duration(days: 6));
    final dailyCompleted = List<int>.filled(7, 0);
    final byProject = <String, int>{};
    var total = 0;
    var completed = 0;
    var overdue = 0;
    var completionDurationTotal = 0;
    var completionDurationCount = 0;

    for (final entry in boards.entries) {
      var projectCount = 0;
      for (final column in entry.value.columns) {
        for (final card in column.cards) {
          total++;
          projectCount++;
          if (card.completed) completed++;

          final dueAt = card.dueDate;
          if (!card.completed && dueAt != null) {
            final due = DateTime.fromMillisecondsSinceEpoch(dueAt);
            final dueDay = DateTime(due.year, due.month, due.day);
            if (dueDay.isBefore(today)) overdue++;
          }

          final completedAt = card.completedAt;
          if (completedAt != null) {
            final completedDate =
                DateTime.fromMillisecondsSinceEpoch(completedAt);
            final completedDay = DateTime(
              completedDate.year,
              completedDate.month,
              completedDate.day,
            );
            final index = completedDay.difference(firstDay).inDays;
            if (index >= 0 && index < dailyCompleted.length) {
              dailyCompleted[index]++;
            }
            if (completedAt >= card.createdAt) {
              completionDurationTotal += completedAt - card.createdAt;
              completionDurationCount++;
            }
          }
        }
      }
      byProject[entry.key] = projectCount;
    }

    return KanbanStatistics(
      total: total,
      completed: completed,
      overdue: overdue,
      completedLast7Days: dailyCompleted,
      averageCompletionHours: completionDurationCount == 0
          ? null
          : completionDurationTotal /
              completionDurationCount /
              Duration.millisecondsPerHour,
      byProject: byProject,
    );
  }
}
