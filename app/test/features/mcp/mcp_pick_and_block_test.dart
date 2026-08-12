import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/kanban/verify_column.dart';
import 'package:kanban/features/mcp/mcp_block_card.dart';
import 'package:kanban/features/mcp/mcp_get_work_items.dart';
import 'package:kanban/features/mcp/mcp_pick_next_card.dart';
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
    tempDir = await Directory.systemTemp.createTemp('kanban_pick_block_');
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

  test('pick_next_card 取待办卡后移入进行中且只返回摘要', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '实施卡');
    expect(cardId, isNotNull);

    final result = await mcpPickNextCard(controller);
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['cardId'], cardId);
    expect(payload['sourceColumn'], '待办');
    expect(payload['fromColumnId'], 'todo');
    expect(payload['columnId'], 'doing');
    expect(payload['columnTitle'], '进行中');
    expect(payload['movedToDoing'], isTrue);
    expect(payload['workMode'], 'normal');
    expect(payload['summary'], isA<Map>());
    expect(payload['summary']['title'], '实施卡');
    expect(payload, isNot(contains('workItems')));
    expect(payload, isNot(contains('suggestedCommitMessage')));
    expect(payload['next'], 'get_work_items');

    final doing = findDoingColumn(controller.board!.columns)!;
    expect(doing.cards.any((card) => card.id == cardId), isTrue);
    final todo = controller.board!.columns.firstWhere((c) => c.id == 'todo');
    expect(todo.cards.any((card) => card.id == cardId), isFalse);
  });

  test('get_work_items 返回未完成 checklist 且不含已完成项', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '带清单');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      todoColumn.id,
      cardId!,
      description: '备注正文',
      checklist: [
        ChecklistItem(id: 'c1', text: '待做'),
        ChecklistItem(id: 'c2', text: '已做', completed: true),
      ],
    );

    final pick = await mcpPickNextCard(controller);
    expect(pick.isError, isNot(true));

    final result = await mcpGetWorkItems(controller, cardId: cardId);
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['cardId'], cardId);
    expect(payload['workMode'], 'normal');
    expect(payload['workItems'], [
      {'kind': 'title', 'text': '带清单'},
      {'kind': 'description', 'text': '备注正文'},
      {'kind': 'checklist', 'id': 'c1', 'text': '待做'},
    ]);
    expect(payload['suggestedCommitMessage'], '带清单\n\n备注正文');
    expect(payload, isNot(contains('attachments')));
  });

  test('pick_next_card 待办空时取待返工且留在待返工列', () async {
    final reworkColumn = controller.board!.columns
        .firstWhere((c) => c.id == KanbanBoard.defaultReworkColumnId);
    final cardId = await controller.addCard(reworkColumn.id, '返工卡');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      reworkColumn.id,
      cardId!,
      verificationFeedback: [
        ChecklistItem(id: 'fb1', text: '修好我'),
      ],
    );

    final result = await mcpPickNextCard(controller);
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['cardId'], cardId);
    expect(payload['sourceColumn'], '待返工');
    expect(payload['workMode'], 'rework');
    expect(payload['movedToDoing'], isFalse);
    expect(payload['columnId'], KanbanBoard.defaultReworkColumnId);
    expect(payload, isNot(contains('workItems')));

    final work = await mcpGetWorkItems(controller, cardId: cardId);
    final workPayload = jsonDecode(_textOf(work)) as Map<String, dynamic>;
    expect(workPayload['workItems'], [
      {
        'kind': 'verificationFeedback',
        'id': 'fb1',
        'text': '修好我',
      },
    ]);

    final rework = controller.board!.columns
        .firstWhere((c) => c.id == KanbanBoard.defaultReworkColumnId);
    expect(rework.cards.any((card) => card.id == cardId), isTrue);
  });

  test('block_card 将卡片移入阻塞中', () async {
    final doingColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'doing');
    final cardId = await controller.addCard(doingColumn.id, '卡住了');
    expect(cardId, isNotNull);

    final result = await mcpBlockCard(controller, cardId: cardId!);
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['ok'], isTrue);
    expect(payload['alreadyInBlockedColumn'], isFalse);
    expect(payload['toColumnId'], 'blocked');

    final blocked = findBlockedColumn(controller.board!.columns)!;
    expect(blocked.cards.any((card) => card.id == cardId), isTrue);
  });

  test('block_card 已在阻塞中时幂等', () async {
    final blockedColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'blocked');
    final cardId = await controller.addCard(blockedColumn.id, '已阻塞');
    expect(cardId, isNotNull);

    final result = await mcpBlockCard(controller, cardId: cardId!);
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['alreadyInBlockedColumn'], isTrue);
  });
}
