import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_move_updated_at_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('列间 moveCard 刷新 updatedAt', () async {
    final cardId = await controller.addCard('todo', '移动刷新时间');
    expect(cardId, isNotNull);

    final before = controller.findCardById(cardId!)!.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final err = await controller.moveCard(
      cardId: cardId,
      fromColumnId: 'todo',
      toColumnId: 'doing',
      toDisplayIndex: 0,
    );
    expect(err, isNull);

    final after = controller.findCardById(cardId)!.updatedAt;
    expect(after, greaterThan(before));
    expect(controller.findColumnIdForCard(cardId), 'doing');
  });
}
