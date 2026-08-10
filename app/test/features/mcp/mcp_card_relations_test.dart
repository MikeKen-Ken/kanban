import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;
  late String firstCardId;
  late String secondCardId;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_mcp_relations_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
    firstCardId = (await controller.addCard('todo', '第一张卡'))!;
    secondCardId = (await controller.addCard('todo', '第二张卡'))!;
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('原子建立和解除双向关联，并保持幂等', () async {
    expect(
      await controller.setCardsRelated(
        firstCardId: firstCardId,
        secondCardId: secondCardId,
        related: true,
      ),
      isNull,
    );
    expect(controller.findCardById(firstCardId)!.relatedIds, [secondCardId]);
    expect(controller.findCardById(secondCardId)!.relatedIds, [firstCardId]);

    await controller.setCardsRelated(
      firstCardId: firstCardId,
      secondCardId: secondCardId,
      related: true,
    );
    expect(controller.findCardById(firstCardId)!.relatedIds, [secondCardId]);
    expect(controller.findCardById(secondCardId)!.relatedIds, [firstCardId]);

    await controller.setCardsRelated(
      firstCardId: firstCardId,
      secondCardId: secondCardId,
      related: false,
    );
    expect(controller.findCardById(firstCardId)!.relatedIds, isEmpty);
    expect(controller.findCardById(secondCardId)!.relatedIds, isEmpty);
  });

  test('撤销恢复关联前两侧的精确状态', () async {
    await controller.updateCardFull(
      'todo',
      firstCardId,
      relatedIds: [secondCardId],
    );
    await controller.setCardsRelated(
      firstCardId: firstCardId,
      secondCardId: secondCardId,
      related: true,
    );
    expect(controller.findCardById(secondCardId)!.relatedIds, [firstCardId]);

    expect(await controller.undoLastAction(), isTrue);
    expect(controller.findCardById(firstCardId)!.relatedIds, [secondCardId]);
    expect(controller.findCardById(secondCardId)!.relatedIds, isEmpty);
  });

  test('卡片不存在或自关联时拒绝且不改变已有数据', () async {
    expect(
      await controller.setCardsRelated(
        firstCardId: firstCardId,
        secondCardId: 'missing',
        related: true,
      ),
      contains('卡片不存在'),
    );
    expect(
      await controller.setCardsRelated(
        firstCardId: firstCardId,
        secondCardId: firstCardId,
        related: true,
      ),
      contains('不能关联自身'),
    );
    expect(controller.findCardById(firstCardId)!.relatedIds, isEmpty);
  });
}
