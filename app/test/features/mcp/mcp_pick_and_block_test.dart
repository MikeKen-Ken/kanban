import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
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
  final text = result.content.whereType<TextContent>().single;
  return text.text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_pick_block_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
  });

  tearDown(() async {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('pick_next_card 默认含 workItems 并移入进行中', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '实施卡');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      todoColumn.id,
      cardId!,
      description: '备注',
    );

    final result = await mcpPickNextCard(controller);
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['cardId'], cardId);
    expect(payload['sourceColumn'], 'To Do');
    expect(payload['fromColumnId'], 'todo');
    expect(payload['columnId'], 'doing');
    expect(payload['columnTitle'], 'In Progress');
    expect(payload['movedToDoing'], isTrue);
    expect(payload['workMode'], 'normal');
    expect(payload['workItems'], [
      {'kind': 'title', 'text': '实施卡'},
      {'kind': 'description', 'text': '备注'},
    ]);
    expect(payload, isNot(contains('summary')));
    expect(payload, isNot(contains('suggestedCommitMessage')));
    expect(payload, isNot(contains('next')));

    final doing = findDoingColumn(controller.board!.columns)!;
    expect(doing.cards.any((card) => card.id == cardId), isTrue);
    final todo = controller.board!.columns.firstWhere((c) => c.id == 'todo');
    expect(todo.cards.any((card) => card.id == cardId), isFalse);
  });

  test('peek_next_card 只判断有无，不领取或移动卡片', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '只读检查卡');
    expect(cardId, isNotNull);

    final result = await mcpPeekNextCard(controller);
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['cardId'], cardId);

    final todo = controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final doing = findDoingColumn(controller.board!.columns)!;
    expect(todo.cards.any((card) => card.id == cardId), isTrue);
    expect(doing.cards.any((card) => card.id == cardId), isFalse);
  });

  test('pick_next_card 注入已同步的 Agent Markdown 对话', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '继续对话');
    expect(cardId, isNotNull);
    expect(
      await controller.setCardAgentConversation(
        cardId!,
        '## 会话\n\n### 用户\n继续修改',
      ),
      isNull,
    );

    final result = await mcpPickNextCard(controller);
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(
      payload['agentConversationMarkdown'],
      '## 会话\n\n### 用户\n继续修改\n',
    );
    final files = payload['fileAttachments'] as List<dynamic>;
    final conversationFile = files.cast<Map<String, dynamic>>().singleWhere(
          (file) => file['fileName'] == KanbanCard.agentConversationFileName,
        );
    expect(conversationFile['included'], isTrue);
    expect(
      utf8.decode(base64Decode(conversationFile['contentBase64'] as String)),
      '## 会话\n\n### 用户\n继续修改\n',
    );
  });

  test('peek_next_card 返回卡片 Agent 覆盖字段', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '覆盖模型卡');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      todoColumn.id,
      cardId!,
      agentEngine: 'cursor',
      agentModelId: 'composer-2.5',
      agentAllowDirtyWorkspace: true,
      agentEnableSandbox: true,
      agentModelParamValues: const {'fast': 'true'},
    );

    final result = await mcpPeekNextCard(controller);
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['cardId'], cardId);
    expect(payload['agentEngine'], 'cursor');
    expect(payload['agentModelId'], 'composer-2.5');
    expect(payload['agentModelParamValues'], {'fast': 'true'});
    expect(payload['agentAllowDirtyWorkspace'], isTrue);
    expect(payload['agentEnableSandbox'], isTrue);
  });

  test('pick_next_card includeWorkItems=false 时不含 workItems', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '只取卡');
    expect(cardId, isNotNull);

    final result = await mcpPickNextCard(controller, includeWorkItems: false);
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['cardId'], cardId);
    expect(payload, isNot(contains('workItems')));
  });

  test('get_work_items 返回未完成 checklist 且不含已完成项与 commit message', () async {
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
    expect(payload, isNot(contains('suggestedCommitMessage')));
    expect(payload, isNot(contains('summary')));
  });

  test('有图片附件元数据时 pick 返回 attachments 字段', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '带图');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      todoColumn.id,
      cardId!,
      attachments: [
        CardAttachment(
          id: 'att-1',
          fileName: 'a.png',
          mimeType: 'image/png',
          order: 0,
          createdAt: 1,
        ),
      ],
    );

    final result = await mcpPickNextCard(controller);
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['attachments'], isA<List>());
    expect(payload['attachments'], hasLength(1));
    expect(payload['attachments'].single['id'], 'att-1');
    expect(payload['attachmentsNote'], contains('已内联'));
  });

  test('pick_next_card 待办与待返工均有卡时优先待返工', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final reworkColumn = controller.board!.columns
        .firstWhere((c) => c.id == KanbanBoard.defaultReworkColumnId);
    final todoCardId = await controller.addCard(todoColumn.id, '待办卡');
    final reworkCardId = await controller.addCard(reworkColumn.id, '返工卡');
    expect(todoCardId, isNotNull);
    expect(reworkCardId, isNotNull);

    final result = await mcpPickNextCard(controller);
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['cardId'], reworkCardId);
    expect(payload['sourceColumn'], 'Rework');
    expect(payload['workMode'], 'normal');
    expect(payload['movedToDoing'], isTrue);
    expect(payload['columnId'], 'doing');

    final doing = findDoingColumn(controller.board!.columns)!;
    expect(doing.cards.any((card) => card.id == reworkCardId), isTrue);
  });

  test('pick_next_card 待办空时取待返工且 workItems 仅含验证反馈', () async {
    final reworkColumn = controller.board!.columns
        .firstWhere((c) => c.id == KanbanBoard.defaultReworkColumnId);
    final cardId = await controller.addCard(reworkColumn.id, '返工卡');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      reworkColumn.id,
      cardId!,
      description: '背景说明',
      commitRef: 'abc1234',
      verificationFeedback: [
        ChecklistItem(id: 'fb1', text: '修好我'),
      ],
    );

    final result = await mcpPickNextCard(controller);
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['cardId'], cardId);
    expect(payload['sourceColumn'], 'Rework');
    expect(payload['workMode'], 'rework');
    expect(payload['commitRef'], 'abc1234');
    expect(payload['movedToDoing'], isTrue);
    expect(payload['columnId'], 'doing');
    expect(payload['workItems'], [
      {
        'kind': 'verificationFeedback',
        'id': 'fb1',
        'text': '修好我',
      },
    ]);

    final doing = findDoingColumn(controller.board!.columns)!;
    expect(doing.cards.any((card) => card.id == cardId), isTrue);
  });

  test('待办空时 peek/pick 领取进行中滞留卡且不重复移列', () async {
    final doingColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'doing');
    final cardId = await controller.addCard(doingColumn.id, '滞留卡');
    expect(cardId, isNotNull);

    final peek = await mcpPeekNextCard(controller);
    final peekPayload = jsonDecode(_textOf(peek)) as Map<String, dynamic>;
    expect(peekPayload['found'], isTrue);
    expect(peekPayload['cardId'], cardId);
    expect(peekPayload['sourceColumn'], 'In Progress');

    final pick = await mcpPickNextCard(controller);
    expect(pick.isError, isNot(true));
    final pickPayload = jsonDecode(_textOf(pick)) as Map<String, dynamic>;
    expect(pickPayload['found'], isTrue);
    expect(pickPayload['cardId'], cardId);
    expect(pickPayload['sourceColumn'], 'In Progress');
    expect(pickPayload['fromColumnId'], 'doing');
    expect(pickPayload['columnId'], 'doing');
    expect(pickPayload['movedToDoing'], isFalse);

    final doing = findDoingColumn(controller.board!.columns)!;
    expect(doing.cards.where((card) => card.id == cardId).length, 1);
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

  test('block_card 传入 reason 时追加到备注末尾', () async {
    final doingColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'doing');
    final cardId = await controller.addCard(doingColumn.id, '卡住了');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      doingColumn.id,
      cardId!,
      description: '原有备注',
    );

    final result = await mcpBlockCard(
      controller,
      cardId: cardId,
      reason: '依赖接口尚未就绪',
    );
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['ok'], isTrue);
    expect(payload['description'], '原有备注\n\nBlock reason: 依赖接口尚未就绪');

    final card = controller.findCardById(cardId)!;
    expect(card.description, '原有备注\n\nBlock reason: 依赖接口尚未就绪');
    final blocked = findBlockedColumn(controller.board!.columns)!;
    expect(blocked.cards.any((c) => c.id == cardId), isTrue);
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
