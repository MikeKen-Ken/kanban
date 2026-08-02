import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/column_card_preferences.dart';
import 'package:kanban/features/project/project_settings.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/features/sync_conflict/sync_conflict.dart';
import 'package:kanban/models/kanban_models.dart';

KanbanCard _card({
  required String id,
  required String title,
  String? description,
  int updatedAt = 100,
  int order = 0,
}) {
  return KanbanCard(
    id: id,
    title: title,
    description: description,
    order: order,
    createdAt: 1,
    updatedAt: updatedAt,
  );
}

KanbanBoard _board({
  required int revision,
  required int updatedAt,
  required List<KanbanColumn> columns,
  String title = '我的看板',
}) {
  return KanbanBoard(
    id: '1',
    title: title,
    updatedAt: updatedAt,
    revision: revision,
    columns: columns,
  );
}

void main() {
  test('仅一侧新增列不丢', () {
    final local = KanbanBoard.empty(id: '1').copyWith(revision: 5, updatedAt: 100);
    final remote = _board(
      revision: 6,
      updatedAt: 200,
      columns: [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: []),
        KanbanColumn(id: 'doing', title: '进行中', order: 1, cards: []),
      ],
    );
    final merged = mergeBoards(local: local, remote: remote);
    expect(merged.columns.map((c) => c.id), contains('done'));
    expect(merged.columns.length, 3);
  });

  test('同字段冲突 → 有 conflictSide 且主侧为较新', () {
    final local = _board(
      revision: 2,
      updatedAt: 100,
      columns: [
        KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: [_card(id: 'c1', title: '本地标题', updatedAt: 100)],
        ),
      ],
    );
    final remote = _board(
      revision: 3,
      updatedAt: 200,
      columns: [
        KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: [_card(id: 'c1', title: '远端标题', updatedAt: 200)],
        ),
      ],
    );
    final merged = mergeBoards(local: local, remote: remote);
    final card = merged.columns.first.cards.single;
    expect(card.title, '远端标题');
    expect(card.hasConflict, isTrue);
    expect(card.conflictSide?.title, '本地标题');
  });

  test('不同字段三路自动合且无冲突标记', () {
    final baseCard = _card(id: 'c1', title: '原标题', description: '原备注', updatedAt: 50);
    final base = _board(
      revision: 1,
      updatedAt: 50,
      columns: [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: [baseCard]),
      ],
    );
    final local = _board(
      revision: 2,
      updatedAt: 100,
      columns: [
        KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: [
            baseCard.copyWith(title: '本地新标题', updatedAt: 100),
          ],
        ),
      ],
    );
    final remote = _board(
      revision: 2,
      updatedAt: 110,
      columns: [
        KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: [
            baseCard.copyWith(description: '远端新备注', updatedAt: 110),
          ],
        ),
      ],
    );
    final merged = mergeBoards(local: local, remote: remote, base: base);
    final card = merged.columns.first.cards.single;
    expect(card.title, '本地新标题');
    expect(card.description, '远端新备注');
    expect(card.hasConflict, isFalse);
  });

  test('删 vs 改 → 冲突而非静默丢删', () {
    final baseCard = _card(id: 'c1', title: '原标题', updatedAt: 50);
    final base = _board(
      revision: 1,
      updatedAt: 50,
      columns: [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: [baseCard]),
      ],
    );
    final local = _board(
      revision: 2,
      updatedAt: 100,
      columns: [
        KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: [baseCard.copyWith(title: '本地改过', updatedAt: 100)],
        ),
      ],
    );
    final remote = _board(
      revision: 2,
      updatedAt: 90,
      columns: [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: []),
      ],
    );
    final merged = mergeBoards(local: local, remote: remote, base: base);
    final card = merged.columns.first.cards.single;
    expect(card.title, '本地改过');
    expect(card.hasConflict, isTrue);
    expect(card.conflictDeleted, isTrue);
  });

  test('Manifest 两侧各建项目 → 并集', () {
    final local = ProjectsManifest(
      projects: [
        const ProjectEntry(id: 'a', title: 'A', updatedAt: 1, revision: 1),
      ],
      updatedAt: 1,
      revision: 1,
    );
    final remote = ProjectsManifest(
      projects: [
        const ProjectEntry(id: 'b', title: 'B', updatedAt: 2, revision: 1),
      ],
      updatedAt: 2,
      revision: 1,
    );
    final merged = mergeManifests(local: local, remote: remote);
    expect(merged.projects.map((p) => p.id).toSet(), {'a', 'b'});
  });

  test('旧 JSON 无 conflict 字段仍可解析', () {
    final card = KanbanCard.fromJson({
      'id': 'c1',
      'title': '标题',
      'order': 0,
      'createdAt': 1,
    });
    expect(card.hasConflict, isFalse);
    expect(card.conflictSide, isNull);
  });

  test('Settings 同字段冲突挂 conflictSide', () {
    final local = const ProjectSettings(
      themeId: 'dark',
      updatedAt: 100,
      revision: 2,
    );
    final remote = const ProjectSettings(
      themeId: 'light',
      updatedAt: 200,
      revision: 2,
    );
    final merged = mergeSettings(local: local, remote: remote);
    expect(merged.themeId, 'light');
    expect(merged.hasConflict, isTrue);
    expect(merged.conflictSide?.themeId, 'dark');
  });

  test('Settings 一侧为空默认桩时不制造冲突', () {
    final local = ProjectSettings(
      doneColumnName: '已完成',
      columnPreferences: {
        'todo': const ColumnCardPreferences(),
      },
      updatedAt: 100,
      revision: 3,
    );
    const remote = ProjectSettings(); // updatedAt=0 revision=0
    final merged = mergeSettings(local: local, remote: remote);
    expect(merged.hasConflict, isFalse);
    expect(merged.revision, 3);
    expect(merged.columnPreferences.containsKey('todo'), isTrue);
  });

  test('Settings 已有空默认桩 conflictSide → 下次合并自动清除', () {
    final local = ProjectSettings(
      doneColumnName: '已完成',
      columnPreferences: {
        'todo': const ColumnCardPreferences(),
      },
      updatedAt: 100,
      revision: 5,
      conflictSide: const ProjectSettings(),
    );
    final remote = local.copyWith(clearConflictSide: true, updatedAt: 90);
    final merged = mergeSettings(local: local, remote: remote);
    expect(merged.hasConflict, isFalse);
    expect(merged.conflictSide, isNull);
    expect(merged.revision, 5);
  });

  test('双侧都删 → 卡片消失', () {
    final baseCard = _card(id: 'c1', title: '原标题', updatedAt: 50);
    final base = _board(
      revision: 1,
      updatedAt: 50,
      columns: [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: [baseCard]),
      ],
    );
    final empty = _board(
      revision: 2,
      updatedAt: 100,
      columns: [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: []),
      ],
    );
    final merged = mergeBoards(local: empty, remote: empty, base: base);
    expect(merged.columns.first.cards, isEmpty);
  });
}
