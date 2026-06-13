import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  test('merge prefers higher revision', () {
    final local = KanbanBoard.empty(id: '1').copyWith(revision: 2, updatedAt: 100);
    final remote = KanbanBoard.empty(id: '1').copyWith(revision: 3, updatedAt: 50);
    expect(local.mergeWith(remote).revision, 3);
  });

  test('merge uses updatedAt when revision equal', () {
    final local = KanbanBoard.empty(id: '1').copyWith(revision: 2, updatedAt: 100);
    final remote = KanbanBoard.empty(id: '1').copyWith(revision: 2, updatedAt: 200);
    expect(local.mergeWith(remote).updatedAt, 200);
  });
}
