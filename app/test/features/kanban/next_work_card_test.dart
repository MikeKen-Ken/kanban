import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/next_work_card.dart';
import 'package:kanban/models/kanban_models.dart';

KanbanCard _card({
  required String id,
  required String title,
  required int updatedAt,
  int? createdAt,
  bool completed = false,
  String? description,
  List<ChecklistItem> checklist = const [],
  List<ChecklistItem> verificationFeedback = const [],
}) {
  final created = createdAt ?? updatedAt;
  return KanbanCard(
    id: id,
    title: title,
    order: 0,
    createdAt: created,
    updatedAt: updatedAt,
    completed: completed,
    description: description,
    checklist: checklist,
    verificationFeedback: verificationFeedback,
  );
}

KanbanBoard _board(List<KanbanColumn> columns) {
  return KanbanBoard(
    id: 'p1',
    title: '测试',
    updatedAt: 1,
    revision: 1,
    columns: columns,
  );
}

void main() {
  test('待办有未完成卡时按 updatedAt 取最新，忽略已完成', () {
    final board = _board([
      KanbanColumn(
        id: 'todo',
        title: '待办',
        order: 0,
        cards: [
          _card(id: 'a', title: '旧', updatedAt: 10),
          _card(id: 'b', title: '新', updatedAt: 30),
          _card(id: 'c', title: '已完成更新', updatedAt: 99, completed: true),
          _card(id: 'd', title: '中', updatedAt: 20),
        ],
      ),
      KanbanColumn(
        id: 'rework',
        title: '待返工',
        order: 1,
        cards: [
          _card(id: 'r', title: '返工更新', updatedAt: 1000),
        ],
      ),
    ]);

    final picked = pickNextWorkCard(board);
    expect(picked, isNotNull);
    expect(picked!.sourceColumn, '待办');
    expect(picked.card.id, 'b');
  });

  test('待办无未完成卡时回退到待返工最新', () {
    final board = _board([
      KanbanColumn(
        id: 'todo',
        title: '待办',
        order: 0,
        cards: [
          _card(id: 'done', title: '完', updatedAt: 50, completed: true),
        ],
      ),
      KanbanColumn(
        id: 'rework',
        title: '待返工',
        order: 1,
        cards: [
          _card(id: 'r1', title: '旧返工', updatedAt: 5),
          _card(id: 'r2', title: '新返工', updatedAt: 8),
        ],
      ),
    ]);

    final picked = pickNextWorkCard(board);
    expect(picked, isNotNull);
    expect(picked!.sourceColumn, '待返工');
    expect(picked.card.id, 'r2');
  });

  test('两列都无未完成卡时返回 null', () {
    final board = _board([
      KanbanColumn(
        id: 'todo',
        title: '待办',
        order: 0,
        cards: [
          _card(id: 'a', title: '完', updatedAt: 1, completed: true),
        ],
      ),
      KanbanColumn(
        id: 'rework',
        title: '待返工',
        order: 1,
        cards: const [],
      ),
    ]);

    expect(pickNextWorkCard(board), isNull);
  });

  test('updatedAt 相同时取 createdAt 更新的', () {
    final newer = pickLatestIncompleteCard([
      _card(id: 'old', title: '早建', updatedAt: 10, createdAt: 1),
      _card(id: 'new', title: '晚建', updatedAt: 10, createdAt: 9),
    ]);
    expect(newer?.id, 'new');
  });

  test('返工 workItems 只含未完成验证反馈', () {
    final card = _card(
      id: 'r',
      title: '旧标题',
      updatedAt: 1,
      description: '旧备注',
      verificationFeedback: [
        ChecklistItem(id: 'fb1', text: '问题一'),
        ChecklistItem(id: 'fb2', text: '问题二', completed: true),
      ],
    );
    expect(isReworkWorkMode(card), isTrue);
    expect(buildCardWorkItems(card), [
      {
        'kind': 'verificationFeedback',
        'id': 'fb1',
        'text': '问题一',
      },
    ]);
    expect(buildCardCommitMessage(card), '问题一\n问题二');
  });

  test('普通模式 workItems 含标题备注与 checklist', () {
    final card = _card(
      id: 'n',
      title: '新功能',
      updatedAt: 1,
      description: '说明',
      checklist: [
        ChecklistItem(id: 'c1', text: '子任务'),
      ],
    );
    expect(isReworkWorkMode(card), isFalse);
    expect(buildCardWorkItems(card), [
      {'kind': 'title', 'text': '新功能'},
      {'kind': 'description', 'text': '说明'},
      {
        'kind': 'checklist',
        'id': 'c1',
        'text': '子任务',
        'completed': false,
      },
    ]);
    expect(buildCardCommitMessage(card), '新功能\n\n说明');
  });
}
