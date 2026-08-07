import 'package:flutter_test/flutter_test.dart';

import 'package:kanban/features/completed_auto_clear/completed_auto_clear.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/settings/app_settings.dart';

KanbanCard _card({
  required String id,
  required int createdAt,
  int? updatedAt,
  int? completedAt,
  bool completed = true,
}) {
  return KanbanCard(
    id: id,
    title: id,
    order: 0,
    createdAt: createdAt,
    updatedAt: updatedAt ?? createdAt,
    completed: completed,
    completedAt: completedAt,
  );
}

KanbanBoard _boardWithDone(List<KanbanCard> doneCards) {
  return KanbanBoard(
    id: 'p1',
    title: '测试',
    updatedAt: 0,
    revision: 0,
    columns: [
      KanbanColumn(id: 'todo', title: '待办', order: 0, cards: const []),
      KanbanColumn(id: 'done', title: '已完成', order: 1, cards: doneCards),
    ],
  );
}

void main() {
  final now = DateTime.utc(2026, 8, 7);

  group('completed_auto_clear 纯逻辑', () {
    test('优先使用 completedAt，缺省时回退 updatedAt', () {
      final withCompleted = _card(
        id: 'a',
        createdAt: 1,
        updatedAt: 100,
        completedAt: 50,
      );
      final withoutCompleted = _card(
        id: 'b',
        createdAt: 1,
        updatedAt: 80,
      );
      expect(completedReferenceMs(withCompleted), 50);
      expect(completedReferenceMs(withoutCompleted), 80);
    });

    test('retainDays=0 表示从不清空', () {
      final board = _boardWithDone([
        _card(
          id: 'old',
          createdAt: 1,
          completedAt: now
              .subtract(const Duration(days: 30))
              .millisecondsSinceEpoch,
        ),
      ]);
      expect(
        selectExpiredCompletedCards(
          board: board,
          doneColumnName: '已完成',
          retainDays: 0,
          now: now,
        ),
        isEmpty,
      );
    });

    test('仅删除超过保留天数的已完成列卡片', () {
      final oldMs =
          now.subtract(const Duration(days: 10)).millisecondsSinceEpoch;
      final recentMs =
          now.subtract(const Duration(days: 2)).millisecondsSinceEpoch;
      final board = KanbanBoard(
        id: 'p1',
        title: '测试',
        updatedAt: 0,
        revision: 0,
        columns: [
          KanbanColumn(
            id: 'todo',
            title: '待办',
            order: 0,
            cards: [
              _card(id: 'todo-old', createdAt: 1, completedAt: oldMs),
            ],
          ),
          KanbanColumn(
            id: 'done',
            title: '已完成',
            order: 1,
            cards: [
              _card(id: 'done-old', createdAt: 1, completedAt: oldMs),
              _card(id: 'done-recent', createdAt: 1, completedAt: recentMs),
            ],
          ),
        ],
      );

      final expired = selectExpiredCompletedCards(
        board: board,
        doneColumnName: '已完成',
        retainDays: 7,
        now: now,
      );
      expect(expired.map((c) => c.id), ['done-old']);
    });

    test('按列名匹配已完成列', () {
      final oldMs =
          now.subtract(const Duration(days: 20)).millisecondsSinceEpoch;
      final board = KanbanBoard(
        id: 'p1',
        title: '测试',
        updatedAt: 0,
        revision: 0,
        columns: [
          KanbanColumn(
            id: 'col-x',
            title: 'Done',
            order: 0,
            cards: [_card(id: 'x', createdAt: 1, completedAt: oldMs)],
          ),
          KanbanColumn(
            id: 'col-y',
            title: '完成归档',
            order: 1,
            cards: [_card(id: 'y', createdAt: 1, completedAt: oldMs)],
          ),
        ],
      );
      final expired = selectExpiredCompletedCards(
        board: board,
        doneColumnName: '完成归档',
        retainDays: 7,
        now: now,
      );
      expect(expired.map((c) => c.id), ['y']);
    });
  });

  group('AppSettings 已完成自动清空天数', () {
    test('默认从不自动清空', () {
      expect(AppSettings.platformDefault().completedAutoClearDays, 0);
    });

    test('序列化往返保留天数', () {
      final settings = AppSettings(
        dragLongPressMs: 200,
        completedAutoClearDays: 7,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.completedAutoClearDays, 7);
    });

    test('旧 JSON 缺字段时默认为 0', () {
      final restored = AppSettings.fromJson({
        'dragLongPressMs': 0,
        'themeMode': 'system',
      });
      expect(restored.completedAutoClearDays, 0);
    });
  });
}
