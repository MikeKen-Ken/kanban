import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/kanban_labels.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('default board has seven columns including rework and inbox', () {
    final board = KanbanBoard.empty(id: 'test');
    expect(board.columns.length, 7);
    expect(
      board.columns.map((c) => c.id).toList(),
      ['todo', 'doing', 'blocked', 'verify', 'rework', 'done', 'inbox'],
    );
    expect(
      board.columns.map((c) => c.title).toList(),
      ['To Do', 'In Progress', 'Blocked', 'Verify', 'Rework', 'Done', 'Inbox'],
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
    expect(loaded.columns.length, 7);
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
        ChecklistItem(id: 'vf1', text: '验证未通过', completed: false),
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
    expect(restored.verificationFeedback.first.text, '验证未通过');
  });

  test('card matches search query', () {
    final card = KanbanCard(
      id: 'c1',
      title: '写报告',
      order: 0,
      createdAt: 0,
      labels: ['work'],
      commitRef: 'deadbeef',
      attachments: [
        CardAttachment(
          id: 'a1',
          fileName: '封面图.jpg',
          mimeType: 'image/jpeg',
          order: 0,
          createdAt: 0,
        ),
      ],
      verificationFeedback: [
        ChecklistItem(id: 'vf1', text: '缺少截图'),
      ],
    );
    expect(card.matchesSearch('报告'), isTrue);
    expect(card.matchesSearch('工作'), isTrue); // 旧 key work →「工作（旧）」
    expect(card.matchesSearch('截图'), isTrue);
    expect(card.matchesSearch('deadbeef'), isTrue);
    expect(card.matchesSearch('封面图'), isTrue);
    expect(card.matchesSearch('不存在'), isFalse);
  });

  test('card matches search by quadrant description', () {
    final card = KanbanCard(
      id: 'c2',
      title: '规划',
      order: 0,
      createdAt: 0,
      labels: ['important_not_urgent'],
    );
    expect(card.matchesSearch('重缓'), isTrue);
    expect(card.matchesSearch('重要不紧急'), isTrue);
  });
}
