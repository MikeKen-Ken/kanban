import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/kanban/verify_column.dart';
import 'package:kanban/features/mcp/mcp_submit_for_verify.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _textOf(CallToolResult result) {
  final content = result.content.single as TextContent;
  return content.text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_submit_verify_');
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

  test('只需 cardId 即可从待办移入待验证，并返回提交信息', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '测试卡');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      todoColumn.id,
      cardId!,
      description: '备注内容',
    );

    final result = await mcpSubmitCardForVerify(
      controller,
      cardId: cardId,
    );
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['suggestedCommitMessage'], '测试卡\n\n备注内容');
    expect(payload['afterGitCommit'], isNotNull);

    final board = controller.board!;
    final verifyColumn = findVerifyColumn(board.columns)!;
    expect(
      verifyColumn.cards.any((card) => card.id == cardId),
      isTrue,
    );
  });

  test('仅传 cardId 时默认勾选全部未完成验证反馈', () async {
    final reworkColumn = controller.board!.columns
        .firstWhere((c) => c.id == KanbanBoard.defaultReworkColumnId);
    final cardId = await controller.addCard(reworkColumn.id, '返工卡');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      reworkColumn.id,
      cardId!,
      verificationFeedback: [
        ChecklistItem(id: 'fb1', text: '问题一'),
        ChecklistItem(id: 'fb2', text: '问题二'),
      ],
    );

    final result = await mcpSubmitCardForVerify(
      controller,
      cardId: cardId,
    );
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['suggestedCommitMessage'], '问题一\n问题二');

    final board = controller.board!;
    final verifyColumn = findVerifyColumn(board.columns)!;
    final card = verifyColumn.cards.firstWhere((c) => c.id == cardId);
    expect(card.verificationFeedback.every((item) => item.completed), isTrue);
  });

  test('completedFeedbackIds 仍可只勾选部分反馈', () async {
    final reworkColumn = controller.board!.columns
        .firstWhere((c) => c.id == KanbanBoard.defaultReworkColumnId);
    final cardId = await controller.addCard(reworkColumn.id, '返工卡');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      reworkColumn.id,
      cardId!,
      verificationFeedback: [
        ChecklistItem(id: 'fb1', text: '问题一'),
        ChecklistItem(id: 'fb2', text: '问题二'),
      ],
    );

    final result = await mcpSubmitCardForVerify(
      controller,
      cardId: cardId,
      completedFeedbackIds: ['fb1'],
    );
    expect(result.isError, isNot(true));

    final board = controller.board!;
    final verifyColumn = findVerifyColumn(board.columns)!;
    final card = verifyColumn.cards.firstWhere((c) => c.id == cardId);
    expect(card.verificationFeedback[0].completed, isTrue);
    expect(card.verificationFeedback[1].completed, isFalse);
  });

  test('可传入 commitRef 写入提交号', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '提交号卡');
    expect(cardId, isNotNull);

    final result = await mcpSubmitCardForVerify(
      controller,
      cardId: cardId!,
      commitRef: 'abc1234',
    );
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['commitRef'], 'abc1234');
    expect(payload.containsKey('afterGitCommit'), isFalse);

    final verifyColumn = findVerifyColumn(controller.board!.columns)!;
    final card = verifyColumn.cards.firstWhere((c) => c.id == cardId);
    expect(card.commitRef, 'abc1234');
  });

  test('卡片已在待验证时可单独补写 commitRef', () async {
    final verifyColumn = findVerifyColumn(controller.board!.columns)!;
    final cardId = await controller.addCard(verifyColumn.id, '补写提交号');
    expect(cardId, isNotNull);

    final result = await mcpSubmitCardForVerify(
      controller,
      cardId: cardId!,
      commitRef: 'deadbeef',
    );
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['alreadyInVerifyColumn'], isTrue);
    expect(payload['commitRef'], 'deadbeef');

    final card = verifyColumn.cards.firstWhere((c) => c.id == cardId);
    expect(card.commitRef, 'deadbeef');
  });
}
