import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/mcp/mcp_set_card_commit_ref.dart';
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
    tempDir = await Directory.systemTemp.createTemp('kanban_commit_ref_');
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

  test('完整 SHA-1 哈希写入时收成 7 位短哈希', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '短哈希卡');
    expect(cardId, isNotNull);

    final result = await mcpSetCardCommitRef(
      controller,
      cardId: cardId!,
      commitRef: 'abcdef0123456789abcdef0123456789abcdef01',
    );
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['commitRef'], 'abcdef0');

    final refreshedColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final refreshed = refreshedColumn.cards.firstWhere((c) => c.id == cardId);
    expect(refreshed.commitRef, 'abcdef0');
  });

  test('只需 cardId 即可写入提交号', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '测试卡');
    expect(cardId, isNotNull);

    final result = await mcpSetCardCommitRef(
      controller,
      cardId: cardId!,
      commitRef: 'abc1234',
    );
    expect(result.isError, isNot(true));
    final payload = jsonDecode(_textOf(result)) as Map<String, dynamic>;
    expect(payload['commitRef'], 'abc1234');

    final refreshedColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final refreshed = refreshedColumn.cards.firstWhere((c) => c.id == cardId);
    expect(refreshed.commitRef, 'abc1234');
  });

  test('clearCommitRef 可清除提交号', () async {
    final todoColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = await controller.addCard(todoColumn.id, '清除测试');
    expect(cardId, isNotNull);
    await controller.updateCardFull(
      todoColumn.id,
      cardId!,
      commitRef: 'deadbeef',
    );

    final result = await mcpSetCardCommitRef(
      controller,
      cardId: cardId,
      clearCommitRef: true,
    );
    expect(result.isError, isNot(true));

    final refreshedColumn =
        controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final refreshed = refreshedColumn.cards.firstWhere((c) => c.id == cardId);
    expect(refreshed.commitRef, isNull);
  });
}
