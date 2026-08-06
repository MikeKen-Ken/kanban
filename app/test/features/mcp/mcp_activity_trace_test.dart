import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/activity/activity_models.dart';
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
    tempDir =
        await Directory.systemTemp.createTemp('kanban_mcp_activity_trace_');
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

  test('ActivityEvent source JSON 往返', () {
    final event = ActivityEvent(
      id: 'e1',
      projectId: 'p1',
      entityType: 'card',
      entityId: 'c1',
      entityTitle: '标题',
      action: ActivityAction.moved,
      occurredAt: 100,
      source: ActivitySource.mcp,
      details: const {'fromColumnId': 'a', 'toColumnId': 'b'},
    );
    final restored = ActivityEvent.fromJson(event.toJson());
    expect(restored.source, ActivitySource.mcp);
    expect(restored.details['toColumnId'], 'b');

    final legacy = ActivityEvent.fromJson({
      'id': 'e2',
      'projectId': 'p1',
      'entityType': 'card',
      'entityId': 'c2',
      'entityTitle': '旧',
      'action': 'updated',
      'occurredAt': 1,
    });
    expect(legacy.source, ActivitySource.user);
  });

  test('当前项目 MCP 移动会记活动且可撤销', () async {
    final columns = controller.board!.columns;
    final fromId = columns.first.id;
    final toId = columns[1].id;
    final cardId = await controller.addCard(fromId, '待挪卡');
    expect(cardId, isNotNull);

    await runMcpForProject(controller, projectA, (projectId) async {
      await controller.moveCard(
        cardId: cardId!,
        fromColumnId: fromId,
        toColumnId: toId,
        toDisplayIndex: 0,
      );
      return mcpJsonResult({'ok': true});
    });

    final events = controller.activityForProject(projectA);
    final moved = events.where((e) => e.action == ActivityAction.moved);
    expect(moved, isNotEmpty);
    expect(moved.first.source, ActivitySource.mcp);
    expect(controller.canUndo, isTrue);
    expect(controller.undoLabel, startsWith('MCP：'));

    final ok = await controller.undoLastAction();
    expect(ok, isTrue);
    final after = controller.board!.columns
        .firstWhere((c) => c.id == fromId)
        .cards
        .any((c) => c.id == cardId);
    expect(after, isTrue);
  });

  test('跨项目 MCP 更新也会记 MCP 活动并可撤销', () async {
    final bBoard = await controller.loadBoardSnapshot(projectB);
    final columnId = bBoard!.columns.first.id;
    late String cardId;

    await runMcpForProject(controller, projectB, (projectId) async {
      cardId = (await controller.addCard(columnId, 'B卡'))!;
      await controller.updateCardFull(
        columnId,
        cardId,
        title: 'B卡已改',
      );
      return mcpJsonResult({'ok': true});
    });

    expect(controller.activeProjectId, projectA);

    final events = controller.activityForProject(projectB);
    final updated = events.where(
      (e) => e.action == ActivityAction.updated && e.entityId == cardId,
    );
    expect(updated, isNotEmpty);
    expect(updated.first.source, ActivitySource.mcp);
    expect(updated.first.entityTitle, 'B卡已改');

    expect(controller.canUndo, isTrue);
    expect(controller.undoLabel, startsWith('MCP：'));
    final ok = await controller.undoLastAction();
    expect(ok, isTrue);

    final restored = await controller.loadBoardSnapshot(projectB);
    final card = restored!.columns
        .expand((c) => c.cards)
        .firstWhere((c) => c.id == cardId);
    expect(card.title, 'B卡');
  });
}
