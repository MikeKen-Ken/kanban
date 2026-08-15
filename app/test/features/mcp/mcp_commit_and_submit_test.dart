import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/kanban/verify_column.dart';
import 'package:kanban/features/mcp/mcp_commit_and_submit_card.dart';
import 'package:kanban/features/mcp/mcp_dispatch_card_gate.dart';
import 'package:kanban/features/mcp/mcp_pick_next_card.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _jsonOf(CallToolResult result) {
  final text = result.content.whereType<TextContent>().single.text;
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<void> _git(String repo, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: repo,
    environment: {
      ...Platform.environment,
      'GIT_AUTHOR_NAME': 'Test',
      'GIT_AUTHOR_EMAIL': 'test@example.com',
      'GIT_COMMITTER_NAME': 'Test',
      'GIT_COMMITTER_EMAIL': 'test@example.com',
    },
  );
  if (result.exitCode != 0) {
    fail('git ${args.join(' ')} 失败：${result.stdout}\n${result.stderr}');
  }
}

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

  test('commit_and_submit_card 提交改动并移入待验证', () async {
    final repo = Directory(p.join(tempDir.path, 'repo'));
    await repo.create();
    await _git(repo.path, ['init']);
    await _git(repo.path, ['config', 'user.email', 'test@example.com']);
    await _git(repo.path, ['config', 'user.name', 'Test']);
    File(p.join(repo.path, 'app.txt')).writeAsStringSync('old\n');
    await _git(repo.path, ['add', '-A']);
    await _git(repo.path, ['commit', '-m', 'init']);

    final todo = controller.board!.columns.firstWhere((c) => c.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '提交卡'))!;
    await controller.updateCardFull(todo.id, cardId, description: '改文件');

    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
      repoPath: repo.path,
    );
    expect(gate.beginAgentSession('worker-a'), isTrue);

    final pick = await mcpPickNextCard(
      controller,
      projectId: controller.activeProjectId,
    );
    expect(pick.isError, isNot(true));

    File(p.join(repo.path, 'app.txt')).writeAsStringSync('new\n');
    final result = await mcpCommitAndSubmitCard(controller, cardId: cardId);
    expect(
      result.isError,
      isNot(true),
      reason: result.content.whereType<TextContent>().map((e) => e.text).join(),
    );
    final payload = _jsonOf(result);
    expect(payload['ok'], isTrue);
    expect(payload['commitRef'], isNotEmpty);
    expect(
      findVerifyColumn(controller.board!.columns)!
          .cards
          .any((card) => card.id == cardId),
      isTrue,
    );
  });
}
