import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;
  late String projectA;
  late String projectB;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_mutation_mutex_');
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

  test('MCP 写 B 与 UI 写 A 并发时各自落盘且不串项目', () async {
    final columnA = controller.board!.columns.first.id;
    final columnB =
        (await controller.loadBoardSnapshot(projectB))!.columns.first.id;

    // 同时启动：MCP 作用域写 B，UI 写当前 A
    final mcpWrite = controller.runOnProject(projectB, () async {
      // 让出事件循环，制造与 UI 写的交错窗口
      await Future<void>.delayed(Duration.zero);
      await controller.addCard(columnB, 'MCP-B卡');
    });
    final uiWrite = () async {
      await Future<void>.delayed(Duration.zero);
      await controller.addCard(columnA, 'UI-A卡');
    }();

    await Future.wait([mcpWrite, uiWrite]);

    expect(controller.activeProjectId, projectA);

    final aHasUi = controller.board!.columns
        .expand((c) => c.cards)
        .any((c) => c.title == 'UI-A卡');
    final aHasMcp = controller.board!.columns
        .expand((c) => c.cards)
        .any((c) => c.title == 'MCP-B卡');
    expect(aHasUi, isTrue);
    expect(aHasMcp, isFalse);

    final bBoard = await controller.loadBoardSnapshot(projectB);
    final bHasMcp = bBoard!.columns
        .expand((c) => c.cards)
        .any((c) => c.title == 'MCP-B卡');
    final bHasUi = bBoard.columns
        .expand((c) => c.cards)
        .any((c) => c.title == 'UI-A卡');
    expect(bHasMcp, isTrue);
    expect(bHasUi, isFalse);
  });

  test('同项目并发写入串行后两张卡都保留', () async {
    final columnId = controller.board!.columns.first.id;
    await Future.wait([
      controller.addCard(columnId, '卡1'),
      controller.addCard(columnId, '卡2'),
    ]);

    final titles = controller.board!.columns
        .expand((c) => c.cards)
        .map((c) => c.title)
        .toSet();
    expect(titles.contains('卡1'), isTrue);
    expect(titles.contains('卡2'), isTrue);
  });

  test('对外项目写入进入撤销栈且带项目作用域', () async {
    final columnB =
        (await controller.loadBoardSnapshot(projectB))!.columns.first.id;
    await controller.runOnProject(projectB, () async {
      await controller.addCard(columnB, '可撤销');
    });
    expect(controller.canUndo, isTrue);
    expect(controller.activeProjectId, projectA);

    final undone = await controller.undoLastAction();
    expect(undone, isTrue);
    expect(controller.canRedo, isTrue);

    final bBoard = await controller.loadBoardSnapshot(projectB);
    expect(
      bBoard!.columns.expand((c) => c.cards).any((c) => c.title == '可撤销'),
      isFalse,
    );

    final redone = await controller.redoLastAction();
    expect(redone, isTrue);
    final restored = await controller.loadBoardSnapshot(projectB);
    expect(
      restored!.columns.expand((c) => c.cards).any((c) => c.title == '可撤销'),
      isTrue,
    );
  });

  test('多个 MCP 与界面连续并发写入后磁盘项目仍保持隔离', () async {
    for (var i = 0; i < 50; i++) {
      await Future.wait([
        controller.addCard('todo', 'UI-A-$i'),
        controller.runOnProject(projectB, () => controller.addCard(
              'todo',
              'MCP-B-$i',
            )),
      ]);
    }

    await Future.wait([
      controller.renameProject(projectA, '项目A-最终'),
      controller.runOnProject(
        projectB,
        () => controller.renameProject(projectB, '项目B-最终'),
      ),
    ]);

    final boardA = await controller.loadBoardSnapshot(projectA);
    final boardB = await controller.loadBoardSnapshot(projectB);
    final titlesA =
        boardA!.columns.expand((column) => column.cards).map((card) => card.title);
    final titlesB =
        boardB!.columns.expand((column) => column.cards).map((card) => card.title);

    expect(boardA.title, '项目A-最终');
    expect(boardB.title, '项目B-最终');
    expect(titlesA.where((title) => title.startsWith('UI-A-')).length, 50);
    expect(titlesA.any((title) => title.startsWith('MCP-B-')), isFalse);
    expect(titlesB.where((title) => title.startsWith('MCP-B-')).length, 50);
    expect(titlesB.any((title) => title.startsWith('UI-A-')), isFalse);
    expect(controller.activeProjectId, projectA);
  });
}
