import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/mcp/mcp_arg_parsers.dart';
import 'package:kanban/features/mcp/mcp_tool_results.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;
  late String projectA;
  late String projectB;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_mcp_binding_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
    projectA = controller.activeProjectId!;
    await controller.createProject('项目B');
    projectB = controller.activeProjectId!;
    await controller.switchProject(projectA);
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('默认列 id 跨项目相同（串项目风险前提）', () async {
    final aCols =
        controller.board!.columns.map((c) => c.id).toList()..sort();
    final bBoard = await controller.loadBoardSnapshot(projectB);
    final bCols = bBoard!.columns.map((c) => c.id).toList()..sort();
    expect(aCols, bCols);
    expect(aCols, containsAll(['todo', 'doing', 'verify', 'rework', 'done']));
  });

  test('多项目省略 projectId 创建类写操作报错', () {
    final resolved = resolveMcpProjectId(
      controller,
      null,
      requireExplicitWhenMultiple: true,
    );
    expect(resolved.error, isNotNull);
    expect(resolved.error!.isError, isTrue);
    final text = (resolved.error!.content.first as TextContent).text;
    expect(text, contains('必须显式传入 projectId'));
  });

  test('runOnProject 期间 uiActiveProjectId 仍为界面项目', () async {
    expect(controller.activeProjectId, projectA);
    await controller.runOnProject(projectB, () async {
      expect(controller.activeProjectId, projectB);
      expect(controller.uiActiveProjectId, projectA);
      final resolved = resolveMcpProjectId(controller, null);
      expect(resolved.projectId, projectA);
    });
    expect(controller.activeProjectId, projectA);
    expect(controller.uiActiveProjectId, projectA);
  });

  test('MCP 项目作用域不会向界面暴露临时项目状态', () async {
    final boardA = controller.board;
    final entered = Completer<void>();
    final release = Completer<void>();

    final mutation = controller.runOnProject(projectB, () async {
      expect(controller.activeProjectId, projectB);
      expect(controller.board?.id, projectB);
      entered.complete();
      await release.future;
    });

    await entered.future;
    expect(controller.activeProjectId, projectA);
    expect(controller.uiActiveProjectId, projectA);
    expect(controller.board, same(boardA));

    release.complete();
    await mutation;
  });

  test('按 cardId 定位项目，不依赖当前激活项目', () async {
    late String cardId;
    await controller.runOnProject(projectB, () async {
      cardId = (await controller.addCard('todo', '只在B'))!;
    });
    expect(controller.activeProjectId, projectA);

    final located = await resolveMcpProjectIdForCard(
      controller,
      cardId: cardId,
    );
    expect(located.error, isNull);
    expect(located.projectId, projectB);
    expect(located.columnId, 'todo');

    final moved = await runMcpForProject(controller, located.projectId,
        (projectId) async {
      expect(projectId, projectB);
      await controller.moveCard(
        cardId: cardId,
        fromColumnId: 'todo',
        toColumnId: 'doing',
        toDisplayIndex: 0,
      );
      return mcpJsonResult({'ok': true, 'projectId': projectId});
    });
    expect(moved.isError, isNot(true));
    expect(controller.activeProjectId, projectA);

    final bBoard = await controller.loadBoardSnapshot(projectB);
    final inDoing = bBoard!.columns
        .firstWhere((c) => c.id == 'doing')
        .cards
        .any((c) => c.id == cardId);
    expect(inDoing, isTrue);

    final aHas = controller.board!.columns
        .expand((c) => c.cards)
        .any((c) => c.id == cardId);
    expect(aHas, isFalse);
  });

  test('显式错误 projectId 与 card 不匹配时报错', () async {
    late String cardId;
    await controller.runOnProject(projectB, () async {
      cardId = (await controller.addCard('todo', 'B卡'))!;
    });
    final located = await resolveMcpProjectIdForCard(
      controller,
      cardId: cardId,
      projectId: projectA,
    );
    expect(located.error, isNotNull);
    final text = (located.error!.content.first as TextContent).text;
    expect(text, contains('未找到卡片'));
  });
}
