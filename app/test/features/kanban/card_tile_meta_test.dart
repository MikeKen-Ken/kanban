import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/card_tile_meta.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  group('countCompletedBlockedBy', () {
    KanbanColumn columnWith(List<KanbanCard> cards) => KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: cards,
        );

    KanbanCard card({
      required String id,
      bool completed = false,
    }) =>
        KanbanCard(
          id: id,
          title: id,
          order: 0,
          createdAt: 0,
          completed: completed,
        );

    test('空依赖返回 0', () {
      expect(
        countCompletedBlockedBy(blockedByIds: const [], columns: const []),
        0,
      );
    });

    test('统计已完成前置；缺失卡视为未完成', () {
      final columns = [
        columnWith([
          card(id: 'a', completed: true),
          card(id: 'b'),
        ]),
      ];
      expect(
        countCompletedBlockedBy(
          blockedByIds: const ['a', 'b', 'missing'],
          columns: columns,
        ),
        1,
      );
    });
  });
}
