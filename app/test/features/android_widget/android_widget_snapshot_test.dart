import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/android_widget/android_widget_snapshot.dart';
import 'package:kanban/models/kanban_models.dart';

KanbanCard _card({
  required String id,
  required String title,
  bool completed = false,
  int? dueDate,
  int updatedAt = 0,
}) {
  return KanbanCard(
    id: id,
    title: title,
    completed: completed,
    dueDate: dueDate,
    updatedAt: updatedAt,
    createdAt: 0,
    order: 0,
  );
}

KanbanBoard _board(List<KanbanColumn> columns) {
  return KanbanBoard(
    id: 'project-1',
    title: '项目 A',
    updatedAt: 1,
    revision: 1,
    columns: columns,
  );
}

void main() {
  final now = DateTime(2026, 8, 14, 10);

  test('buildAndroidWidgetSnapshot prioritizes overdue and today cards', () {
    final board = _board([
      KanbanColumn(
        id: 'todo',
        title: '待办',
        order: 0,
        cards: [
          _card(id: 'todo-1', title: '普通待办', updatedAt: 50),
        ],
      ),
      KanbanColumn(
        id: 'doing',
        title: '进行中',
        order: 1,
        cards: [
          _card(
            id: 'overdue-1',
            title: '逾期任务',
            dueDate: DateTime(2026, 8, 10).millisecondsSinceEpoch,
            updatedAt: 10,
          ),
          _card(
            id: 'today-1',
            title: '今天到期',
            dueDate: DateTime(2026, 8, 14, 18).millisecondsSinceEpoch,
            updatedAt: 20,
          ),
        ],
      ),
    ]);

    final snapshot = buildAndroidWidgetSnapshot(
      board: board,
      projectName: '项目 A',
      now: now,
    );

    expect(snapshot.overdueCount, 1);
    expect(snapshot.todayCount, 1);
    expect(snapshot.todoCount, 1);
    expect(snapshot.items.map((item) => item.title).toList(), [
      '逾期任务',
      '今天到期',
      '普通待办',
    ]);
    expect(snapshot.items.map((item) => item.badge).toList(), [
      '逾期',
      '今日',
      '待办',
    ]);
  });

  test('buildAndroidWidgetSnapshot includes rework column cards', () {
    final board = _board([
      KanbanColumn(
        id: 'rework',
        title: '待返工',
        order: 0,
        cards: [
          _card(id: 'rework-1', title: '返工卡', updatedAt: 30),
        ],
      ),
    ]);

    final snapshot = buildAndroidWidgetSnapshot(
      board: board,
      projectName: '项目 A',
      now: now,
    );

    expect(snapshot.items.length, 1);
    expect(snapshot.items.first.title, '返工卡');
    expect(snapshot.items.first.badge, '返工');
    expect(snapshot.todoCount, 0);
  });
}
