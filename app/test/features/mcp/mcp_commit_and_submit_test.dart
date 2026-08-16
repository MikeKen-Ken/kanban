import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/mcp/mcp_commit_and_submit_card.dart';
import 'package:kanban/features/mcp/mcp_dispatch_card_gate.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;
  final gate = McpDispatchCardGate.instance;

  setUp(() async {
    gate.debugReset();
    tempDir = await Directory.systemTemp.createTemp('kanban_commit_submit_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
  });

  tearDown(() async {
    gate.debugReset();
    controller.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('Agent 自提交入口一律拒绝，必须走 ready_to_submit', () async {
    final todo = controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '自提交卡'))!;
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
    );
    expect(gate.beginAgentSession('worker-a'), isTrue);

    final result = await mcpCommitAndSubmitCard(controller, cardId: cardId);
    expect(result.isError, isTrue);
    expect(
      result.content.whereType<TextContent>().first.text,
      contains('ready_to_submit'),
    );
  });
}
