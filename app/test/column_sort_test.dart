import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/column_card_preferences.dart';
import 'package:kanban/features/kanban/kanban_labels.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  test('column sort defaults to updatedAt', () {
    expect(const ColumnCardPreferences().sortMode, CardSortMode.updatedAt);
    expect(CardSortMode.fromName(null), CardSortMode.updatedAt);
    expect(CardSortMode.fromName('unknown'), CardSortMode.updatedAt);
  });

  test('all columns default to updatedAt when no preference is stored', () {
    expect(
      defaultSortModeForColumn(isDoneColumn: false),
      CardSortMode.updatedAt,
    );
    expect(
      defaultSortModeForColumn(isDoneColumn: true),
      CardSortMode.updatedAt,
    );
    expect(
      resolveColumnCardPreferences(isDoneColumn: true).sortMode,
      CardSortMode.updatedAt,
    );
    expect(
      resolveColumnCardPreferences(
        stored: const ColumnCardPreferences(sortMode: CardSortMode.priority),
        isDoneColumn: true,
      ).sortMode,
      CardSortMode.priority,
    );
  });

  test('sortColumnCards keeps pinned cards on top', () {
    final cards = [
      KanbanCard(id: 'a', title: 'A', order: 0, createdAt: 1, updatedAt: 1),
      KanbanCard(id: 'b', title: 'B', order: 1, createdAt: 2, updatedAt: 2),
      KanbanCard(id: 'c', title: 'C', order: 2, createdAt: 3, updatedAt: 3),
    ];

    final sorted = sortColumnCards(
      cards,
      sortMode: CardSortMode.name,
      pinnedCardIds: const ['c', 'a'],
    );

    expect(sorted.map((card) => card.id).toList(), ['c', 'a', 'b']);
  });

  test('custom sort uses stored order for unpinned cards', () {
    final cards = [
      KanbanCard(id: 'a', title: 'A', order: 2, createdAt: 1, updatedAt: 1),
      KanbanCard(id: 'b', title: 'B', order: 0, createdAt: 2, updatedAt: 2),
      KanbanCard(id: 'c', title: 'C', order: 1, createdAt: 3, updatedAt: 3),
    ];

    final sorted = sortColumnCards(
      cards,
      sortMode: CardSortMode.custom,
      pinnedCardIds: const [],
    );

    expect(sorted.map((card) => card.id).toList(), ['b', 'c', 'a']);
  });

  test('priority sort puts high priority first', () {
    final cards = [
      KanbanCard(
        id: 'a',
        title: 'A',
        order: 0,
        createdAt: 1,
        updatedAt: 1,
        priority: CardPriority.low,
      ),
      KanbanCard(
        id: 'b',
        title: 'B',
        order: 1,
        createdAt: 2,
        updatedAt: 2,
        priority: CardPriority.high,
      ),
    ];

    final sorted = sortColumnCards(
      cards,
      sortMode: CardSortMode.priority,
      pinnedCardIds: const [],
    );

    expect(sorted.first.id, 'b');
  });

  test('updatedAt sort puts most recently updated first', () {
    final cards = [
      KanbanCard(id: 'a', title: 'A', order: 0, createdAt: 1, updatedAt: 1),
      KanbanCard(id: 'b', title: 'B', order: 1, createdAt: 2, updatedAt: 3),
      KanbanCard(id: 'c', title: 'C', order: 2, createdAt: 3, updatedAt: 2),
    ];

    final sorted = sortColumnCards(
      cards,
      sortMode: CardSortMode.updatedAt,
      pinnedCardIds: const [],
    );

    expect(sorted.map((card) => card.id).toList(), ['b', 'c', 'a']);
  });
}
