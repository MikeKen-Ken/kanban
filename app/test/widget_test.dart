import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/kanban_labels.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('default board has six columns including rework', () {
    final board = KanbanBoard.empty(id: 'test');
    expect(board.columns.length, 6);
    expect(
      board.columns.map((c) => c.id).toList(),
      ['todo', 'doing', 'blocked', 'verify', 'rework', 'done'],
    );
    expect(
      board.columns.map((c) => c.title).toList(),
      ['待办', '进行中', '阻塞中', '待验证', '待返工', '已完成'],
    );
  });

  test('board storage saves each column to separate json', () async {
    final tempDir = await Directory.systemTemp.createTemp('kanban_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = BoardStorage(baseDirectory: tempDir, prefs: prefs);
    final board = KanbanBoard.empty(id: 'split-test');
    await storage.saveBoard(board.id, board);

    final dataDir = Directory(p.join(tempDir.path, 'kanban'));
    final projectDir = Directory(
      p.join(dataDir.path, 'projects', board.id),
    );
    final boardFile = File(p.join(projectDir.path, 'board.json'));
    final todoFile = File(p.join(projectDir.path, 'columns', 'todo.json'));

    expect(await boardFile.exists(), isTrue);
    expect(await todoFile.exists(), isTrue);
    expect(await boardFile.readAsString(), contains('"version": 2'));
    expect(await todoFile.readAsString(), contains('"title": "待办"'));

    final loaded = await storage.loadBoard(board.id);
    expect(loaded.columns.length, 6);
    expect(loaded.columns.first.id, 'todo');
    expect(
      loaded.columns.map((c) => c.id),
      containsAll(['blocked', 'verify', 'rework']),
    );
  });

  test('card json roundtrip with extended fields', () {
    final card = KanbanCard(
      id: 'c1',
      title: '任务',
      order: 0,
      createdAt: 1000,
      completed: true,
      dueDate: 2000,
      priority: CardPriority.high,
      labels: ['work'],
      checklist: [
        ChecklistItem(id: 'cl1', text: '子任务', completed: true),
      ],
      verificationFeedback: [
        ChecklistItem(id: 'vf1', text: '验收未过', completed: false),
      ],
    );
    final restored = KanbanCard.fromJson(card.toJson());
    expect(restored.completed, isTrue);
    expect(restored.dueDate, 2000);
    expect(restored.priority, CardPriority.high);
    expect(restored.labels, ['work']);
    expect(restored.checklist.length, 1);
    expect(restored.checklist.first.completed, isTrue);
    expect(restored.verificationFeedback.length, 1);
    expect(restored.verificationFeedback.first.text, '验收未过');
  });

  test('card matches search query', () {
    final card = KanbanCard(
      id: 'c1',
      title: '写报告',
      order: 0,
      createdAt: 0,
      labels: ['work'],
      verificationFeedback: [
        ChecklistItem(id: 'vf1', text: '缺少截图'),
      ],
    );
    expect(card.matchesSearch('报告'), isTrue);
    expect(card.matchesSearch('工作'), isTrue);
    expect(card.matchesSearch('截图'), isTrue);
    expect(card.matchesSearch('不存在'), isFalse);
  });

  test('ensureReworkColumn inserts between verify and done', () {
    final legacy = KanbanBoard(
      id: 'legacy',
      title: '旧板',
      updatedAt: 1,
      revision: 1,
      columns: [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: const []),
        KanbanColumn(id: 'doing', title: '进行中', order: 1, cards: const []),
        KanbanColumn(id: 'blocked', title: '阻塞中', order: 2, cards: const []),
        KanbanColumn(id: 'verify', title: '待验证', order: 3, cards: const []),
        KanbanColumn(id: 'done', title: '已完成', order: 4, cards: const []),
      ],
    );
    final ensured = legacy.ensureReworkColumn();
    expect(ensured.columns.map((c) => c.title).toList(), [
      '待办',
      '进行中',
      '阻塞中',
      '待验证',
      '待返工',
      '已完成',
    ]);
    final already = KanbanBoard.empty(id: 'ok');
    expect(identical(already.ensureReworkColumn(), already), isTrue);
  });

  test('ensureReworkColumn 已有自定义 id 同名列时不新建', () {
    final board = KanbanBoard(
      id: 'custom',
      title: '板',
      updatedAt: 1,
      revision: 1,
      columns: [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: const []),
        KanbanColumn(id: 'verify', title: '待验证', order: 1, cards: const []),
        KanbanColumn(
          id: 'uuid-rework',
          title: '待返工',
          order: 2,
          cards: const [],
        ),
        KanbanColumn(id: 'done', title: '已完成', order: 3, cards: const []),
      ],
    );
    final ensured = board.ensureReworkColumn();
    expect(
      ensured.columns.where((c) => c.title == '待返工').length,
      1,
    );
    expect(
      ensured.columns.any((c) => c.id == KanbanBoard.defaultReworkColumnId),
      isFalse,
    );
    expect(ensured.columns.map((c) => c.id).toList(), [
      'todo',
      'verify',
      'uuid-rework',
      'done',
    ]);
  });

  test('ensureReworkColumn 合并多个同名待返工列', () {
    final board = KanbanBoard(
      id: 'dup',
      title: '板',
      updatedAt: 1,
      revision: 1,
      columns: [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: const []),
        KanbanColumn(id: 'verify', title: '待验证', order: 1, cards: const []),
        KanbanColumn(
          id: 'uuid-a',
          title: '待返工',
          order: 2,
          cards: [
            KanbanCard(
              id: 'c1',
              title: '卡1',
              order: 0,
              createdAt: 1,
              updatedAt: 1,
            ),
          ],
        ),
        KanbanColumn(
          id: KanbanBoard.defaultReworkColumnId,
          title: '待返工',
          order: 3,
          cards: [
            KanbanCard(
              id: 'c2',
              title: '卡2',
              order: 0,
              createdAt: 1,
              updatedAt: 1,
            ),
          ],
        ),
        KanbanColumn(id: 'done', title: '已完成', order: 4, cards: const []),
      ],
    );
    final ensured = board.ensureReworkColumn();
    final reworks =
        ensured.columns.where((c) => c.title == '待返工').toList();
    expect(reworks, hasLength(1));
    expect(reworks.single.id, KanbanBoard.defaultReworkColumnId);
    expect(reworks.single.cards.map((c) => c.id).toList(), ['c2', 'c1']);
    expect(
      ensured.columns.map((c) => c.title).toList(),
      ['待办', '待验证', '待返工', '已完成'],
    );
  });
}
