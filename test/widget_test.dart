import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  test('default board has three columns', () {
    final board = KanbanBoard.empty(id: 'test');
    expect(board.columns.length, 3);
  });
}
