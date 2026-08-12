import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/kanban/verify_column.dart';
import 'package:kanban/features/mcp/mcp_pick_next_card.dart';
import 'package:kanban/features/mcp/mcp_prepare_card_submission.dart';
import 'package:kanban/features/mcp/mcp_submit_consultation.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _jsonOf(CallToolResult result) {
  final text = result.content.whereType<TextContent>().single.text;
  return jsonDecode(text) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_mcp_workflow_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('prepare_card_submission 使用取卡时冻结的普通任务范围', () async {
    final todo = controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '只读准备'))!;
    await controller.updateCardFull(
      todo.id,
      cardId,
      description: '提交正文',
      checklist: [
        ChecklistItem(id: 'todo', text: '待完成子任务'),
        ChecklistItem(id: 'done', text: '历史子任务', completed: true),
      ],
    );

    final pick = await mcpPickNextCard(controller);
    expect(pick.isError, isNot(true));
    final doingColumnId = controller.findColumnIdForCard(cardId)!;
    await controller.updateCardFull(
      doingColumnId,
      cardId,
      checklist: [
        ChecklistItem(
          id: 'todo',
          text: '待完成子任务',
          completed: true,
        ),
        ChecklistItem(id: 'done', text: '历史子任务', completed: true),
        ChecklistItem(id: 'late', text: '实施中新增子任务'),
      ],
    );

    final result = await mcpPrepareCardSubmission(
      controller,
      cardId: cardId,
    );

    expect(result.isError, isNot(true));
    expect(
      _jsonOf(result)['suggestedCommitMessage'],
      '只读准备\n\n提交正文\n\n- 待完成子任务',
    );
    expect(controller.findColumnIdForCard(cardId), doingColumnId);
  });

  test('prepare_card_submission 返工时使用取卡时冻结的验证反馈', () async {
    final rework = controller.board!.columns.firstWhere(
      (column) => column.id == KanbanBoard.defaultReworkColumnId,
    );
    final cardId = (await controller.addCard(rework.id, '返工卡'))!;
    await controller.updateCardFull(
      rework.id,
      cardId,
      verificationFeedback: [
        ChecklistItem(id: 'fb1', text: '修复问题一'),
        ChecklistItem(id: 'done', text: '历史反馈', completed: true),
      ],
    );

    final pick = await mcpPickNextCard(controller);
    expect(pick.isError, isNot(true));
    await controller.updateCardFull(
      rework.id,
      cardId,
      verificationFeedback: [
        ChecklistItem(id: 'fb1', text: '修复问题一', completed: true),
        ChecklistItem(id: 'late', text: '实施中新增反馈'),
      ],
    );

    final result = await mcpPrepareCardSubmission(
      controller,
      cardId: cardId,
    );

    expect(result.isError, isNot(true));
    final payload = _jsonOf(result);
    expect(payload['workMode'], 'rework');
    expect(payload['suggestedCommitMessage'], '修复问题一');
    expect(payload['incompleteFeedbackIds'], ['fb1']);
  });

  test('submit_consultation 追加答复并移入待验证', () async {
    final todo = controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '咨询卡'))!;
    await controller.updateCardFull(
      todo.id,
      cardId,
      description: '原备注',
      labels: const ['consultation'],
    );

    final result = await mcpSubmitConsultation(
      controller,
      cardId: cardId,
      responseMarkdown: '## 答复\n\n结论',
    );

    expect(result.isError, isNot(true));
    expect(_jsonOf(result)['responseAppended'], isTrue);
    final verify = findVerifyColumn(controller.board!.columns)!;
    final card = verify.cards.firstWhere((item) => item.id == cardId);
    expect(card.description, '原备注\n\n## 答复\n\n结论');
  });

  test('submit_consultation 拒绝无 consultation 标签的卡片', () async {
    final todo = controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '普通卡'))!;

    final result = await mcpSubmitConsultation(
      controller,
      cardId: cardId,
      responseMarkdown: '答复',
    );

    expect(result.isError, isTrue);
    expect(controller.findColumnIdForCard(cardId), todo.id);
  });
}
