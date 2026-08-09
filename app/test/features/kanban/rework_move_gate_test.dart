import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/kanban/move_to_rework_on_new_feedback.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_rework_gate_');
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

  test('无验证反馈时 moveCard 入待返工失败且不落盘', () async {
    final cardId = await controller.addCard('verify', '无反馈卡');
    expect(cardId, isNotNull);

    final err = await controller.moveCard(
      cardId: cardId!,
      fromColumnId: 'verify',
      toColumnId: KanbanBoard.defaultReworkColumnId,
      toDisplayIndex: 0,
    );

    expect(err, reworkMoveRequiresFeedbackMessage);
    expect(controller.findColumnIdForCard(cardId), 'verify');
    final rework = controller.board!.columns
        .firstWhere((c) => c.id == KanbanBoard.defaultReworkColumnId);
    expect(rework.cards.any((c) => c.id == cardId), isFalse);
  });

  test('有验证反馈时允许 moveCard 入待返工', () async {
    final cardId = await controller.addCard('verify', '有反馈卡');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      'verify',
      cardId!,
      verificationFeedback: [
        ChecklistItem(id: 'vf1', text: '请返工'),
      ],
    );

    final err = await controller.moveCard(
      cardId: cardId,
      fromColumnId: 'verify',
      toColumnId: KanbanBoard.defaultReworkColumnId,
      toDisplayIndex: 0,
    );

    expect(err, isNull);
    expect(
      controller.findColumnIdForCard(cardId),
      KanbanBoard.defaultReworkColumnId,
    );
  });

  test('先写入新反馈再移入待返工（自动移入路径）成功', () async {
    final cardId = await controller.addCard('verify', '自动移入卡');
    expect(cardId, isNotNull);

    await controller.updateCardFull(
      'verify',
      cardId!,
      verificationFeedback: [
        ChecklistItem(id: 'new-vf', text: '新增验收意见'),
      ],
    );

    final err = await controller.moveCard(
      cardId: cardId,
      fromColumnId: 'verify',
      toColumnId: KanbanBoard.defaultReworkColumnId,
      toDisplayIndex: 0,
    );

    expect(err, isNull);
    expect(
      controller.findColumnIdForCard(cardId),
      KanbanBoard.defaultReworkColumnId,
    );
  });
}
