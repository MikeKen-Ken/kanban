import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/automations/automation_models.dart';
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

  test('验证反馈全部完成时 moveCard 入待返工失败且不落盘', () async {
    final cardId = await controller.addCard('verify', '反馈已完成卡');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      'verify',
      cardId!,
      verificationFeedback: [
        ChecklistItem(id: 'vf1', text: '已修复', completed: true),
      ],
    );

    final err = await controller.moveCard(
      cardId: cardId,
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

  test('写入未完成验证反馈后由控制器自动移入待返工', () async {
    final cardId = await controller.addCard('verify', '有反馈卡');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      'verify',
      cardId!,
      verificationFeedback: [
        ChecklistItem(id: 'vf1', text: '请返工'),
      ],
    );

    expect(
      controller.findColumnIdForCard(cardId),
      KanbanBoard.defaultReworkColumnId,
    );
  });

  test('未完成反馈存在时拒绝离开待返工到其他列', () async {
    final cardId = await controller.addCard('verify', '不得离开返工到其他列');
    expect(cardId, isNotNull);

    await controller.updateCardFull(
      'verify',
      cardId!,
      verificationFeedback: [
        ChecklistItem(id: 'vf1', text: '仍需修复'),
      ],
    );

    final err = await controller.moveCard(
      cardId: cardId,
      fromColumnId: KanbanBoard.defaultReworkColumnId,
      toColumnId: 'todo',
      toDisplayIndex: 0,
    );

    expect(err, incompleteVerificationFeedbackBlocksReworkExitMessage);
    expect(
      controller.findColumnIdForCard(cardId),
      KanbanBoard.defaultReworkColumnId,
    );
  });

  test('未完成反馈存在时允许从待返工移入进行中或阻塞中', () async {
    final cardId = await controller.addCard('verify', '可继续实施');
    expect(cardId, isNotNull);

    await controller.updateCardFull(
      'verify',
      cardId!,
      verificationFeedback: [
        ChecklistItem(id: 'vf1', text: '仍需修复'),
      ],
    );

    final doingErr = await controller.moveCard(
      cardId: cardId,
      fromColumnId: KanbanBoard.defaultReworkColumnId,
      toColumnId: 'doing',
      toDisplayIndex: 0,
    );

    expect(doingErr, isNull);
    expect(controller.findColumnIdForCard(cardId), 'doing');

    final blockedErr = await controller.moveCard(
      cardId: cardId,
      fromColumnId: 'doing',
      toColumnId: 'blocked',
      toDisplayIndex: 0,
    );

    expect(blockedErr, isNull);
    expect(controller.findColumnIdForCard(cardId), 'blocked');
  });

  test('未完成反馈存在时拒绝移入已完成列且不落盘', () async {
    final cardId = await controller.addCard('verify', '不得完成');
    expect(cardId, isNotNull);

    await controller.updateCardFull(
      'verify',
      cardId!,
      verificationFeedback: [
        ChecklistItem(id: 'vf1', text: '仍需修复'),
      ],
    );

    final err = await controller.moveCard(
      cardId: cardId,
      fromColumnId: KanbanBoard.defaultReworkColumnId,
      toColumnId: 'done',
      toDisplayIndex: 0,
    );

    expect(err, incompleteVerificationFeedbackBlocksReworkExitMessage);
    expect(
      controller.findColumnIdForCard(cardId),
      KanbanBoard.defaultReworkColumnId,
    );
  });

  test('待返工同列排序不受未完成反馈门禁影响', () async {
    final cardId = await controller.addCard('verify', '同列排序');
    await controller.updateCardFull(
      'verify',
      cardId!,
      verificationFeedback: [ChecklistItem(id: 'vf1', text: '仍需修复')],
    );

    final err = await controller.moveCard(
      cardId: cardId,
      fromColumnId: KanbanBoard.defaultReworkColumnId,
      toColumnId: KanbanBoard.defaultReworkColumnId,
      toDisplayIndex: 0,
    );

    expect(err, isNull);
    expect(controller.findColumnIdForCard(cardId),
        KanbanBoard.defaultReworkColumnId);
  });

  test('所有验证反馈完成后允许离开待返工', () async {
    final cardId = await controller.addCard('verify', '反馈已闭环');
    await controller.updateCardFull(
      'verify',
      cardId!,
      verificationFeedback: [ChecklistItem(id: 'vf1', text: '已修复')],
    );
    await controller.updateCardFull(
      KanbanBoard.defaultReworkColumnId,
      cardId,
      verificationFeedback: [
        ChecklistItem(id: 'vf1', text: '已修复', completed: true),
      ],
    );

    final err = await controller.moveCard(
      cardId: cardId,
      fromColumnId: KanbanBoard.defaultReworkColumnId,
      toColumnId: 'verify',
      toDisplayIndex: 0,
    );

    expect(err, isNull);
    expect(controller.findColumnIdForCard(cardId), 'verify');
  });

  test('未完成反馈存在时 toggleCardCompleted 拒绝且不触发完成副作用', () async {
    final cardId = await controller.addCard('verify', '禁止完成');
    await controller.updateCardFull(
      'verify',
      cardId!,
      verificationFeedback: [ChecklistItem(id: 'vf1', text: '仍需修复')],
    );

    final err = await controller.toggleCardCompleted(
      KanbanBoard.defaultReworkColumnId,
      cardId,
    );

    expect(err, incompleteVerificationFeedbackBlocksProgressMessage);
    expect(controller.findCardById(cardId)!.completed, isFalse);
    expect(controller.findColumnIdForCard(cardId),
        KanbanBoard.defaultReworkColumnId);
  });

  test('updateCardFull 不能直接绕过门禁标记完成', () async {
    final cardId = await controller.addCard('verify', '直接完成');
    await controller.updateCardFull(
      'verify',
      cardId!,
      verificationFeedback: [ChecklistItem(id: 'vf1', text: '仍需修复')],
    );

    final err = await controller.updateCardFull(
      KanbanBoard.defaultReworkColumnId,
      cardId,
      completed: true,
    );

    expect(err, incompleteVerificationFeedbackBlocksProgressMessage);
    expect(controller.findCardById(cardId)!.completed, isFalse);
  });

  test('自动化不能把有未完成反馈的卡片移到已完成列', () async {
    final cardId = await controller.addCard('verify', '自动化门禁');
    await controller.updateCardFull(
      'verify',
      cardId!,
      dueDate: DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch,
      verificationFeedback: [ChecklistItem(id: 'vf1', text: '仍需修复')],
    );
    await controller.saveProjectSettings(
      controller.projectSettings.copyWith(
        automationRules: const [
          AutomationRule(
            id: 'complete-overdue',
            name: '逾期后完成',
            trigger: AutomationTrigger.overdue,
            action: AutomationActionType.moveToDoneColumn,
          ),
        ],
      ),
    );

    await controller.runOverdueAutomations();

    expect(controller.findCardById(cardId)!.completed, isFalse);
    expect(controller.findColumnIdForCard(cardId),
        KanbanBoard.defaultReworkColumnId);
  });
}
