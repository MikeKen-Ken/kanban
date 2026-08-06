import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/mcp/mcp_arg_parsers.dart';
import 'package:kanban/features/mcp/mcp_tool_results.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;
  late String projectA;
  late String projectB;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_mcp_project_scope_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
    // create() 会初始化一个默认项目并切过去
    projectA = controller.activeProjectId!;
    await controller.createProject('项目B');
    projectB = controller.activeProjectId!;
    // 回到 A，模拟「用户正在看 A」
    await controller.switchProject(projectA);
    expect(controller.activeProjectId, projectA);
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('ensureMcpProject 校验存在但不切换 UI', () async {
    final before = controller.activeProjectId;
    final err = await ensureMcpProject(controller, projectB);
    expect(err, isNull);
    expect(controller.activeProjectId, before);
    expect(controller.activeProjectId, projectA);

    final missing = await ensureMcpProject(controller, 'not-exist');
    expect(missing, isNotNull);
    expect(missing!.isError, isTrue);
    expect(controller.activeProjectId, projectA);
  });

  test('runOnProject 写入 B 后 UI 仍停在 A，且 B 数据已落盘', () async {
    final columnId = controller.board!.columns.first.id;
    // B 的列 id 与默认板相同（empty board）
    await controller.runOnProject(projectB, () async {
      final id = await controller.addCard(columnId, '来自 MCP 的卡');
      expect(id, isNotNull);
    });

    expect(controller.activeProjectId, projectA);
    // A 看板不应出现该卡
    final aHas = controller.board!.columns
        .expand((c) => c.cards)
        .any((c) => c.title == '来自 MCP 的卡');
    expect(aHas, isFalse);

    final bBoard = await controller.loadBoardSnapshot(projectB);
    expect(bBoard, isNotNull);
    final bHas = bBoard!.columns
        .expand((c) => c.cards)
        .any((c) => c.title == '来自 MCP 的卡');
    expect(bHas, isTrue);
  });

  test('runMcpForProject 对 B 操作不切换 active', () async {
    final columnId = (await controller.loadBoardSnapshot(projectB))!
        .columns
        .first
        .id;
    final result = await runMcpForProject(
      controller,
      projectB,
      (projectId) async {
        expect(projectId, projectB);
        // 作用域内 active 临时为 B，但结束后应恢复
        final cardId = await controller.addCard(columnId, 'MCP 作用域卡');
        expect(cardId, isNotNull);
        return mcpJsonResult({'ok': true, 'cardId': cardId});
      },
    );
    expect(result.isError, isNot(true));
    expect(controller.activeProjectId, projectA);

    final bBoard = await controller.loadBoardSnapshot(projectB);
    expect(
      bBoard!.columns.expand((c) => c.cards).any((c) => c.title == 'MCP 作用域卡'),
      isTrue,
    );
  });

  test('显式 switchProject 仍可切换', () async {
    await controller.switchProject(projectB);
    expect(controller.activeProjectId, projectB);
    await controller.switchProject(projectA);
    expect(controller.activeProjectId, projectA);
  });

  test('MCP 创建项目数据不会切换界面当前项目', () async {
    final beforeBoard = controller.board;

    final projectC = await controller.createProjectData('项目C');

    expect(controller.activeProjectId, projectA);
    expect(controller.uiActiveProjectId, projectA);
    expect(controller.board, same(beforeBoard));
    expect(controller.projects.any((project) => project.id == projectC), isTrue);
    expect((await controller.loadBoardSnapshot(projectC))?.title, '项目C');
  });
}
