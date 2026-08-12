import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/kanban/need_resource_column_gate.dart';
import 'package:kanban/features/kanban/verify_column.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_need_resource_');
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

  test('贴上缺资源标签后自动移入阻塞中', () async {
    final cardId = await controller.addCard('todo', '缺资源卡');
    expect(cardId, isNotNull);

    final err = await controller.updateCardFull(
      'todo',
      cardId!,
      labels: const [needResourceLabelKey],
    );
    expect(err, isNull);
    expect(controller.findColumnIdForCard(cardId), defaultBlockedColumnId);
  });

  test('带缺资源标签时不能拖出阻塞中', () async {
    final cardId = await controller.addCard(
      'todo',
      '卡住',
      labels: const [needResourceLabelKey],
    );
    expect(cardId, isNotNull);
    expect(controller.findColumnIdForCard(cardId!), defaultBlockedColumnId);

    final err = await controller.moveCard(
      cardId: cardId,
      fromColumnId: defaultBlockedColumnId,
      toColumnId: 'todo',
      toDisplayIndex: 0,
    );
    expect(err, needResourceMustStayInBlockedMessage);
    expect(controller.findColumnIdForCard(cardId), defaultBlockedColumnId);
  });

  test('带缺资源标签时可在阻塞中列内重排', () async {
    final firstId = await controller.addCard(
      defaultBlockedColumnId,
      '第一',
      labels: const [needResourceLabelKey],
    );
    final secondId = await controller.addCard(
      defaultBlockedColumnId,
      '第二',
      labels: const [needResourceLabelKey],
    );
    expect(firstId, isNotNull);
    expect(secondId, isNotNull);

    final err = await controller.moveCard(
      cardId: secondId!,
      fromColumnId: defaultBlockedColumnId,
      toColumnId: defaultBlockedColumnId,
      toDisplayIndex: 0,
    );
    expect(err, isNull);
    expect(controller.findColumnIdForCard(secondId), defaultBlockedColumnId);
  });

  test('创建时带缺资源标签直接落入阻塞中', () async {
    final cardId = await controller.addCard(
      'doing',
      '新建缺资源',
      labels: const [needResourceLabelKey],
    );
    expect(cardId, isNotNull);
    expect(controller.findColumnIdForCard(cardId!), defaultBlockedColumnId);
  });

  test('去掉缺资源标签后可移出阻塞中', () async {
    final cardId = await controller.addCard(
      'todo',
      '可恢复',
      labels: const [needResourceLabelKey],
    );
    expect(cardId, isNotNull);
    expect(controller.findColumnIdForCard(cardId!), defaultBlockedColumnId);

    final clearErr = await controller.updateCardFull(
      defaultBlockedColumnId,
      cardId,
      labels: const [],
    );
    expect(clearErr, isNull);

    final moveErr = await controller.moveCard(
      cardId: cardId,
      fromColumnId: defaultBlockedColumnId,
      toColumnId: 'todo',
      toDisplayIndex: 0,
    );
    expect(moveErr, isNull);
    expect(controller.findColumnIdForCard(cardId), 'todo');
  });
}
