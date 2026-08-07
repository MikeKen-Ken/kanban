import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/kanban/transfer_card.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('resolveTransferTargetColumnId', () {
    test('有源列同名标题时优先匹配该列', () {
      final board = KanbanBoard(
        id: 'p1',
        title: '测',
        updatedAt: 1,
        revision: 1,
        columns: [
          KanbanColumn(id: 'todo', title: '待办', order: 0, cards: const []),
          KanbanColumn(id: 'doing-b', title: '进行中', order: 1, cards: const []),
          KanbanColumn(id: 'done', title: '已完成', order: 2, cards: const []),
        ],
      );
      expect(
        resolveTransferTargetColumnId(board, sourceColumnTitle: '进行中'),
        'doing-b',
      );
    });

    test('源列标题 trim 后精确匹配', () {
      final board = KanbanBoard(
        id: 'p1',
        title: '测',
        updatedAt: 1,
        revision: 1,
        columns: [
          KanbanColumn(id: 'todo', title: '待办', order: 0, cards: const []),
          KanbanColumn(id: 'review', title: '  评审  ', order: 1, cards: const []),
        ],
      );
      expect(
        resolveTransferTargetColumnId(board, sourceColumnTitle: '评审'),
        'review',
      );
      expect(
        resolveTransferTargetColumnId(board, sourceColumnTitle: '  评审  '),
        'review',
      );
    });

    test('无同名列时回退 todo', () {
      final board = KanbanBoard.empty(id: 'p1');
      expect(
        resolveTransferTargetColumnId(board, sourceColumnTitle: '评审'),
        'todo',
      );
    });

    test('无同名且无 todo id 时按标题「待办」匹配', () {
      final board = KanbanBoard(
        id: 'p1',
        title: '测',
        updatedAt: 1,
        revision: 1,
        columns: [
          KanbanColumn(id: 'inbox', title: '待办', order: 0, cards: const []),
          KanbanColumn(id: 'done', title: '已完成', order: 1, cards: const []),
        ],
      );
      expect(
        resolveTransferTargetColumnId(board, sourceColumnTitle: '不存在'),
        'inbox',
      );
    });

    test('无同名且无待办时取第一个非完成列', () {
      final board = KanbanBoard(
        id: 'p1',
        title: '测',
        updatedAt: 1,
        revision: 1,
        columns: [
          KanbanColumn(id: 'doing', title: '进行中', order: 0, cards: const []),
          KanbanColumn(id: 'done', title: '已完成', order: 1, cards: const []),
        ],
      );
      expect(resolveTransferTargetColumnId(board), 'doing');
    });

    test('仅有完成列时仍返回该列', () {
      final board = KanbanBoard(
        id: 'p1',
        title: '测',
        updatedAt: 1,
        revision: 1,
        columns: [
          KanbanColumn(id: 'done', title: '已完成', order: 0, cards: const []),
        ],
      );
      expect(resolveTransferTargetColumnId(board), 'done');
    });

    test('空列返回 null', () {
      final board = KanbanBoard(
        id: 'p1',
        title: '测',
        updatedAt: 1,
        revision: 1,
        columns: const [],
      );
      expect(resolveTransferTargetColumnId(board), isNull);
    });

    test('未给源列标题时仍优先 todo', () {
      final board = KanbanBoard.empty(id: 'p1');
      expect(resolveTransferTargetColumnId(board), 'todo');
    });
  });

  group('BoardController.transferCardToProject', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late Directory tempDir;
    late BoardController controller;
    late String projectA;
    late String projectB;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kanban_transfer_');
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

    test('转移到目标项目同名列（非待办）', () async {
      final cardId = await controller.addCard('doing', '同名列卡');
      expect(cardId, isNotNull);

      final error = await controller.transferCardToProject(
        fromColumnId: 'doing',
        cardId: cardId!,
        targetProjectId: projectB,
      );
      expect(error, isNull);

      final bBoard = await controller.loadBoardSnapshot(projectB);
      final doing = bBoard!.columns.firstWhere((c) => c.id == 'doing');
      expect(doing.title, '进行中');
      expect(doing.cards.any((c) => c.id == cardId), isTrue);
      final todo = bBoard.columns.firstWhere((c) => c.id == 'todo');
      expect(todo.cards.any((c) => c.id == cardId), isFalse);
    });

    test('无同名列时落到目标项目待办列，源项目不再显示', () async {
      // 源项目自定义列标题，目标默认板无同名
      await controller.addColumn('评审');
      final reviewCol = controller.board!.columns
          .firstWhere((c) => c.title == '评审');
      final cardId = await controller.addCard(reviewCol.id, '跨项目卡');
      expect(cardId, isNotNull);

      final error = await controller.transferCardToProject(
        fromColumnId: reviewCol.id,
        cardId: cardId!,
        targetProjectId: projectB,
      );
      expect(error, isNull);

      expect(
        controller.board!.columns
            .expand((c) => c.cards)
            .any((c) => c.id == cardId),
        isFalse,
      );

      final bBoard = await controller.loadBoardSnapshot(projectB);
      final transferred = bBoard!.columns
          .expand((c) => c.cards)
          .where((c) => c.id == cardId)
          .single;
      expect(transferred.title, '跨项目卡');
      final todo = bBoard.columns.firstWhere((c) => c.id == 'todo');
      expect(todo.cards.any((c) => c.id == cardId), isTrue);
    });

    test('从待办列转移仍落到目标待办', () async {
      final cardId = await controller.addCard('todo', '待办卡');
      expect(cardId, isNotNull);

      final error = await controller.transferCardToProject(
        fromColumnId: 'todo',
        cardId: cardId!,
        targetProjectId: projectB,
      );
      expect(error, isNull);

      final bBoard = await controller.loadBoardSnapshot(projectB);
      final todo = bBoard!.columns.firstWhere((c) => c.id == 'todo');
      expect(todo.cards.any((c) => c.id == cardId), isTrue);
    });

    test('不能转到自己', () async {
      final cardId = await controller.addCard('todo', '本项目卡');
      final error = await controller.transferCardToProject(
        fromColumnId: 'todo',
        cardId: cardId!,
        targetProjectId: projectA,
      );
      expect(error, '不能转移到当前项目');
      expect(
        controller.board!.columns
            .expand((c) => c.cards)
            .any((c) => c.id == cardId),
        isTrue,
      );
    });

    test('只有一个项目时拒绝', () async {
      final cardId = await controller.addCard('todo', '孤岛卡');
      await controller.deleteProject(projectB);
      expect(controller.projects.length, 1);

      final error = await controller.transferCardToProject(
        fromColumnId: 'todo',
        cardId: cardId!,
        targetProjectId: 'missing',
      );
      expect(error, '没有其他可转移的项目');
    });

    test('跨列转移到同名列，并清空依赖关联', () async {
      final blockerId = await controller.addCard('todo', '前置');
      final cardId = await controller.addCard('doing', '被转');
      await controller.updateCardFull(
        'doing',
        cardId!,
        blockedByIds: [blockerId!],
        relatedIds: [blockerId],
        completed: true,
      );

      final error = await controller.transferCardToProject(
        fromColumnId: 'doing',
        cardId: cardId,
        targetProjectId: projectB,
      );
      expect(error, isNull);

      final bBoard = await controller.loadBoardSnapshot(projectB);
      final transferred = bBoard!.columns
          .expand((c) => c.cards)
          .where((c) => c.id == cardId)
          .single;
      expect(transferred.blockedByIds, isEmpty);
      expect(transferred.relatedIds, isEmpty);
      expect(transferred.completed, isFalse);
      final doing = bBoard.columns.firstWhere((c) => c.id == 'doing');
      expect(doing.cards.any((c) => c.id == cardId), isTrue);
    });

    test('撤销可把卡片转回原项目原列', () async {
      final cardId = await controller.addCard('doing', '可撤销');
      await controller.transferCardToProject(
        fromColumnId: 'doing',
        cardId: cardId!,
        targetProjectId: projectB,
      );
      expect(
        controller.board!.columns
            .expand((c) => c.cards)
            .any((c) => c.id == cardId),
        isFalse,
      );

      final undone = await controller.undoLastAction();
      expect(undone, isTrue);
      final restored = controller.board!.columns
          .firstWhere((c) => c.id == 'doing')
          .cards
          .where((c) => c.id == cardId);
      expect(restored.length, 1);
    });
  });
}
