import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/kanban_motion.dart';
import 'package:kanban/models/kanban_models.dart';

KanbanCard _card(String id) {
  return KanbanCard(
    id: id,
    title: id,
    order: 0,
    createdAt: 1,
    updatedAt: 1,
  );
}

void main() {
  test('首次填充不播放进入动画', () {
    final next = [_card('a'), _card('b')];
    final result = reconcileTrackedKanbanCards(previous: const [], next: next);
    expect(result.map((e) => e.card.id), ['a', 'b']);
    expect(result.every((e) => !e.animateEnter && !e.leaving), isTrue);
  });

  test('单张移出时在原位保留离场条目', () {
    final previous = [
      TrackedKanbanCard(card: _card('a')),
      TrackedKanbanCard(card: _card('b')),
      TrackedKanbanCard(card: _card('c')),
    ];
    final result = reconcileTrackedKanbanCards(
      previous: previous,
      next: [_card('a'), _card('c')],
    );
    expect(result.map((e) => e.card.id), ['a', 'b', 'c']);
    expect(result[1].leaving, isTrue);
    expect(result[0].leaving, isFalse);
    expect(result[2].leaving, isFalse);
  });

  test('单张移入时标记进入动画', () {
    final previous = [
      TrackedKanbanCard(card: _card('a')),
      TrackedKanbanCard(card: _card('c')),
    ];
    final result = reconcileTrackedKanbanCards(
      previous: previous,
      next: [_card('a'), _card('b'), _card('c')],
    );
    expect(result.map((e) => e.card.id), ['a', 'b', 'c']);
    expect(result[1].animateEnter, isTrue);
    expect(result[0].animateEnter, isFalse);
  });

  test('大批量变更时跳过动画并直接对齐', () {
    final previous = [
      for (final id in ['a', 'b', 'c', 'd']) TrackedKanbanCard(card: _card(id)),
    ];
    final next = [_card('w'), _card('x'), _card('y'), _card('z')];
    final result = reconcileTrackedKanbanCards(previous: previous, next: next);
    expect(result.map((e) => e.card.id), ['w', 'x', 'y', 'z']);
    expect(result.every((e) => !e.leaving && !e.animateEnter), isTrue);
  });
}
