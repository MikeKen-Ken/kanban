import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/column_card_preferences.dart';
import 'package:kanban/features/project/project_settings.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/features/sync_conflict/sync_conflict.dart';
import 'package:kanban/features/wallpapers/wallpaper_models.dart';
import 'package:kanban/features/trash/trash_models.dart';
import 'package:kanban/models/kanban_models.dart';

KanbanCard _card({
  required String id,
  required String title,
  String? description,
  int updatedAt = 100,
  int order = 0,
  int createdAt = 1,
}) {
  return KanbanCard(
    id: id,
    title: title,
    description: description,
    order: order,
    createdAt: createdAt,
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
  test('两路内容相同时保留最早正数 createdAt', () {
    final local = PlacedCard(
      card: _card(id: 'c1', title: '同标题', createdAt: 0, updatedAt: 200),
      columnId: 'todo',
    );
    final remote = PlacedCard(
      card: _card(id: 'c1', title: '同标题', createdAt: 50, updatedAt: 100),
      columnId: 'todo',
    );
    final result = mergeCardTwoWay(local: local, remote: remote);
    expect(result.placed?.card.createdAt, 50);
    expect(result.placed?.card.updatedAt, 200);
  });

  test('三路合并取最早正数 createdAt', () {
    final base = PlacedCard(
      card: _card(id: 'c1', title: '原', createdAt: 40, updatedAt: 40),
      columnId: 'todo',
    );
    final local = PlacedCard(
      card: _card(id: 'c1', title: '本地', createdAt: 0, updatedAt: 100),
      columnId: 'todo',
    );
    final remote = PlacedCard(
      card: _card(
          id: 'c1',
          title: '原',
          description: '远端备注',
          createdAt: 90,
          updatedAt: 110),
      columnId: 'todo',
    );
    final result = mergeCardThreeWay(base: base, local: local, remote: remote);
    expect(result.placed?.card.createdAt, 40);
    expect(result.placed?.card.title, '本地');
    expect(result.placed?.card.description, '远端备注');
  });

  test('仅一侧新增列不丢', () {
    final local =
        KanbanBoard.empty(id: '1').copyWith(revision: 5, updatedAt: 100);
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
    expect(merged.columns.map((c) => c.id), contains('blocked'));
    expect(merged.columns.map((c) => c.id), contains('verify'));
    expect(merged.columns.map((c) => c.id), contains('rework'));
    expect(merged.columns.length, 6);
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
    final baseCard =
        _card(id: 'c1', title: '原标题', description: '原备注', updatedAt: 50);
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

  test('验证反馈三路自动合且不丢字段', () {
    final baseCard = _card(id: 'c1', title: '原标题', updatedAt: 50);
    final base = _board(
      revision: 1,
      updatedAt: 50,
      columns: [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: [baseCard]),
      ],
    );
    final localFeedback = [
      ChecklistItem(id: 'vf1', text: '本地反馈', completed: false),
    ];
    final local = _board(
      revision: 2,
      updatedAt: 100,
      columns: [
        KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: [
            baseCard.copyWith(
              verificationFeedback: localFeedback,
              updatedAt: 100,
            ),
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
            baseCard.copyWith(title: '远端标题', updatedAt: 110),
          ],
        ),
      ],
    );
    final merged = mergeBoards(local: local, remote: remote, base: base);
    final card = merged.columns.first.cards.single;
    expect(card.title, '远端标题');
    expect(card.verificationFeedback.single.text, '本地反馈');
    expect(card.hasConflict, isFalse);
  });

  test('仅一侧新增待返工列不丢', () {
    final local =
        KanbanBoard.empty(id: '1').copyWith(revision: 5, updatedAt: 100);
    final remote = _board(
      revision: 6,
      updatedAt: 200,
      columns: [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: []),
        KanbanColumn(id: 'doing', title: '进行中', order: 1, cards: []),
        KanbanColumn(id: 'verify', title: '待验证', order: 2, cards: []),
        KanbanColumn(id: 'done', title: '已完成', order: 3, cards: []),
      ],
    );
    final merged = mergeBoards(local: local, remote: remote);
    expect(merged.columns.map((c) => c.id), contains('rework'));
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
    final local = const ProjectsManifest(
      projects: [
        ProjectEntry(id: 'a', title: 'A', updatedAt: 1, revision: 1),
      ],
      updatedAt: 1,
      revision: 1,
    );
    final remote = const ProjectsManifest(
      projects: [
        ProjectEntry(id: 'b', title: 'B', updatedAt: 2, revision: 1),
      ],
      updatedAt: 2,
      revision: 1,
    );
    final merged = mergeManifests(local: local, remote: remote);
    expect(merged.projects.map((p) => p.id).toSet(), {'a', 'b'});
  });

  test('Manifest 远端删且本地相对 base 未改 → 采纳删除', () {
    const keep = ProjectEntry(id: 'a', title: 'A', updatedAt: 1, revision: 1);
    const gone = ProjectEntry(id: 'b', title: 'B', updatedAt: 1, revision: 1);
    final base = const ProjectsManifest(
      projects: [keep, gone],
      updatedAt: 1,
      revision: 1,
    );
    final local = base;
    final remote = const ProjectsManifest(
      projects: [keep],
      updatedAt: 2,
      revision: 2,
    );
    final merged = mergeManifests(local: local, remote: remote, base: base);
    expect(merged.projects.map((p) => p.id).toSet(), {'a'});
  });

  test('Manifest 远端删但本地改过 → 保留并挂 conflictDeleted', () {
    const keep = ProjectEntry(id: 'a', title: 'A', updatedAt: 1, revision: 1);
    const goneBase =
        ProjectEntry(id: 'b', title: 'B', updatedAt: 1, revision: 1);
    const goneLocal =
        ProjectEntry(id: 'b', title: 'B改过', updatedAt: 50, revision: 2);
    final base = const ProjectsManifest(
      projects: [keep, goneBase],
      updatedAt: 1,
      revision: 1,
    );
    final local = const ProjectsManifest(
      projects: [keep, goneLocal],
      updatedAt: 50,
      revision: 2,
    );
    final remote = const ProjectsManifest(
      projects: [keep],
      updatedAt: 2,
      revision: 2,
    );
    final merged = mergeManifests(local: local, remote: remote, base: base);
    expect(merged.projects.map((p) => p.id).toSet(), {'a', 'b'});
    final b = merged.projects.firstWhere((p) => p.id == 'b');
    expect(b.title, 'B改过');
    expect(b.conflictDeleted, isTrue);
  });

  test('Manifest 无 base 时远端缺项目 → 保留本地（避免误删离线新建）', () {
    final local = const ProjectsManifest(
      projects: [
        ProjectEntry(id: 'a', title: 'A', updatedAt: 1, revision: 1),
        ProjectEntry(id: 'new', title: '新建', updatedAt: 9, revision: 1),
      ],
      updatedAt: 9,
      revision: 2,
    );
    final remote = const ProjectsManifest(
      projects: [
        ProjectEntry(id: 'a', title: 'A', updatedAt: 1, revision: 1),
      ],
      updatedAt: 1,
      revision: 1,
    );
    final merged = mergeManifests(local: local, remote: remote);
    expect(merged.projects.map((p) => p.id).toSet(), {'a', 'new'});
  });

  test('Manifest 本地删且远端相对 base 未改 → 保持删除', () {
    const keep = ProjectEntry(id: 'a', title: 'A', updatedAt: 1, revision: 1);
    const gone = ProjectEntry(id: 'b', title: 'B', updatedAt: 1, revision: 1);
    final base = const ProjectsManifest(
      projects: [keep, gone],
      updatedAt: 1,
      revision: 1,
    );
    final local = const ProjectsManifest(
      projects: [keep],
      updatedAt: 3,
      revision: 2,
    );
    final remote = base;
    final merged = mergeManifests(local: local, remote: remote, base: base);
    expect(merged.projects.map((p) => p.id).toSet(), {'a'});
  });

  test('Manifest 本地删但远端改过 → 保留远端并挂 conflictDeleted', () {
    const keep = ProjectEntry(id: 'a', title: 'A', updatedAt: 1, revision: 1);
    const goneBase =
        ProjectEntry(id: 'b', title: 'B', updatedAt: 1, revision: 1);
    const goneRemote =
        ProjectEntry(id: 'b', title: '远端改', updatedAt: 80, revision: 3);
    final base = const ProjectsManifest(
      projects: [keep, goneBase],
      updatedAt: 1,
      revision: 1,
    );
    final local = const ProjectsManifest(
      projects: [keep],
      updatedAt: 3,
      revision: 2,
    );
    final remote = const ProjectsManifest(
      projects: [keep, goneRemote],
      updatedAt: 80,
      revision: 3,
    );
    final merged = mergeManifests(local: local, remote: remote, base: base);
    expect(merged.projects.map((p) => p.id).toSet(), {'a', 'b'});
    final b = merged.projects.firstWhere((p) => p.id == 'b');
    expect(b.title, '远端改');
    expect(b.conflictDeleted, isTrue);
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

  test('Settings 背景图字段冲突挂 conflictSide', () {
    final local = const ProjectSettings(
      backgroundAttachmentId: 'bg-local',
      backgroundOverlayOpacity: 0.2,
      updatedAt: 100,
      revision: 2,
    );
    final remote = const ProjectSettings(
      backgroundAttachmentId: 'bg-remote',
      backgroundOverlayOpacity: 0.5,
      updatedAt: 200,
      revision: 2,
    );
    final merged = mergeSettings(local: local, remote: remote);
    expect(merged.backgroundAttachmentId, 'bg-remote');
    expect(merged.hasConflict, isTrue);
    expect(merged.conflictSide?.backgroundAttachmentId, 'bg-local');
  });

  test('Settings 三路合并可分别采纳背景与遮罩', () {
    const base = ProjectSettings(
      backgroundAttachmentId: 'bg-base',
      backgroundOverlayOpacity: 0.4,
      updatedAt: 10,
      revision: 1,
    );
    final local = base.copyWith(
      backgroundAttachmentId: 'bg-local',
      updatedAt: 20,
      revision: 2,
    );
    final remote = base.copyWith(
      backgroundOverlayOpacity: 0.6,
      updatedAt: 30,
      revision: 2,
    );
    final merged = mergeSettings(local: local, remote: remote, base: base);
    expect(merged.hasConflict, isFalse);
    expect(merged.backgroundAttachmentId, 'bg-local');
    expect(merged.backgroundOverlayOpacity, closeTo(0.6, 0.001));
  });

  test('Settings 三路合并可分别采纳卡片不透明度', () {
    const base = ProjectSettings(
      cardSurfaceOpacity: 1.0,
      updatedAt: 10,
      revision: 1,
    );
    final local = base.copyWith(
      cardSurfaceOpacity: 0.7,
      updatedAt: 20,
      revision: 2,
    );
    final remote = base.copyWith(
      doneColumnName: '完成',
      updatedAt: 30,
      revision: 2,
    );
    final merged = mergeSettings(local: local, remote: remote, base: base);
    expect(merged.hasConflict, isFalse);
    expect(merged.cardSurfaceOpacity, closeTo(0.7, 0.001));
    expect(merged.doneColumnName, '完成');
  });

  test('ProjectSettings 背景字段序列化往返', () {
    final settings = const ProjectSettings(
      backgroundAttachmentId: 'bg-1',
      backgroundOverlayOpacity: 0.55,
      cardSurfaceOpacity: 0.8,
      updatedAt: 42,
      revision: 3,
    );
    final roundtrip = ProjectSettings.fromJson(settings.toJson());
    expect(roundtrip.backgroundAttachmentId, 'bg-1');
    expect(roundtrip.backgroundOverlayOpacity, closeTo(0.55, 0.001));
    expect(roundtrip.cardSurfaceOpacity, closeTo(0.8, 0.001));
    expect(roundtrip.hasBackgroundImage, isTrue);
  });

  test('ProjectSettings 随机壁纸配置序列化往返', () {
    const settings = ProjectSettings(
      backgroundAttachmentId: 'w1',
      wallpaperIds: ['w1', 'w2'],
      wallpaperPlaybackMode: WallpaperPlaybackMode.random,
      wallpaperIntervalSeconds: 60,
      updatedAt: 42,
      revision: 3,
    );
    final roundtrip = ProjectSettings.fromJson(settings.toJson());
    expect(roundtrip.wallpaperIds, ['w1', 'w2']);
    expect(roundtrip.wallpaperPlaybackMode, WallpaperPlaybackMode.random);
    expect(roundtrip.wallpaperIntervalSeconds, 60);
  });

  test('Settings 三路合并可分别采纳壁纸配置与主题', () {
    const base = ProjectSettings(updatedAt: 1, revision: 1);
    final local = base.copyWith(
      backgroundAttachmentId: 'w1',
      wallpaperIds: ['w1', 'w2'],
      wallpaperPlaybackMode: WallpaperPlaybackMode.random,
      wallpaperIntervalSeconds: 30,
      updatedAt: 2,
      revision: 2,
    );
    final remote = base.copyWith(themeId: 'dark', updatedAt: 3, revision: 2);
    final merged = mergeSettings(local: local, remote: remote, base: base);
    expect(merged.wallpaperIds, ['w1', 'w2']);
    expect(merged.wallpaperPlaybackMode, WallpaperPlaybackMode.random);
    expect(merged.wallpaperIntervalSeconds, 30);
    expect(merged.themeId, 'dark');
    expect(merged.hasConflict, isFalse);
  });

  test('旧 settings.json 缺背景字段时使用安全默认值', () {
    final settings = ProjectSettings.fromJson({
      'doneColumnName': '已完成',
      'updatedAt': 1,
      'revision': 1,
    });
    expect(settings.backgroundAttachmentId, isEmpty);
    expect(
      settings.backgroundOverlayOpacity,
      ProjectSettings.defaultBackgroundOverlayOpacity,
    );
    expect(
      settings.cardSurfaceOpacity,
      ProjectSettings.defaultCardSurfaceOpacity,
    );
    expect(settings.wallpaperPlaybackMode, WallpaperPlaybackMode.fixed);
    expect(
      settings.wallpaperIntervalSeconds,
      ProjectSettings.legacyWallpaperIntervalSeconds,
    );
  });

  test('新项目默认每 10 秒随机轮播', () {
    const settings = ProjectSettings();
    expect(settings.wallpaperPlaybackMode, WallpaperPlaybackMode.random);
    expect(settings.wallpaperIntervalSeconds, 10);
  });

  test('Settings 一侧为空默认桩时不制造冲突', () {
    final local = const ProjectSettings(
      doneColumnName: '已完成',
      columnPreferences: {
        'todo': ColumnCardPreferences(),
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
    final local = const ProjectSettings(
      doneColumnName: '已完成',
      columnPreferences: {
        'todo': ColumnCardPreferences(),
      },
      updatedAt: 100,
      revision: 5,
      conflictSide: ProjectSettings(),
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

  test('工作区远端删未改项目 → 从清单移除并写入回收站', () {
    const keepEntry =
        ProjectEntry(id: 'a', title: 'A', updatedAt: 1, revision: 1);
    const goneEntry =
        ProjectEntry(id: 'b', title: 'B', updatedAt: 1, revision: 1);
    final keepBoard =
        KanbanBoard.empty(id: 'a').copyWith(revision: 1, updatedAt: 1);
    final goneBoard =
        KanbanBoard.empty(id: 'b').copyWith(revision: 1, updatedAt: 1);
    final base = ProjectWorkspaceSnapshot(
      manifest: const ProjectsManifest(
        projects: [keepEntry, goneEntry],
        updatedAt: 1,
        revision: 1,
      ),
      boards: {'a': keepBoard, 'b': goneBoard},
      settings: {
        'a': const ProjectSettings(),
        'b': const ProjectSettings(),
      },
    );
    final remoteTrash = TrashBin(
      items: [
        TrashItem.forProject(
          trashId: 't1',
          deletedAt: 200,
          entry: goneEntry,
          board: goneBoard,
          settings: const ProjectSettings(),
          projectTrash: TrashBin.empty,
        ),
      ],
      updatedAt: 200,
      revision: 1,
    );
    final local = base;
    final remote = ProjectWorkspaceSnapshot(
      manifest: const ProjectsManifest(
        projects: [keepEntry],
        updatedAt: 2,
        revision: 2,
      ),
      boards: {'a': keepBoard},
      settings: {'a': const ProjectSettings()},
      appTrash: remoteTrash,
    );

    final merged = mergeWorkspaces(local: local, remote: remote, base: base);
    expect(merged.manifest.projects.map((p) => p.id).toSet(), {'a'});
    expect(merged.boards.containsKey('b'), isFalse);
    expect(
      merged.appTrash.items.any(
        (i) => i.type == TrashItemType.project && i.projectId == 'b',
      ),
      isTrue,
    );
  });

  test('工作区远端删但本地改过看板内容 → conflictDeleted', () {
    const keepEntry =
        ProjectEntry(id: 'a', title: 'A', updatedAt: 1, revision: 1);
    const goneEntry =
        ProjectEntry(id: 'b', title: 'B', updatedAt: 1, revision: 1);
    final keepBoard =
        KanbanBoard.empty(id: 'a').copyWith(revision: 1, updatedAt: 1);
    final goneBase =
        KanbanBoard.empty(id: 'b').copyWith(revision: 1, updatedAt: 1);
    final goneLocal =
        goneBase.copyWith(revision: 5, updatedAt: 500, title: '本地板');
    final base = ProjectWorkspaceSnapshot(
      manifest: const ProjectsManifest(
        projects: [keepEntry, goneEntry],
        updatedAt: 1,
        revision: 1,
      ),
      boards: {'a': keepBoard, 'b': goneBase},
      settings: {
        'a': const ProjectSettings(),
        'b': const ProjectSettings(),
      },
    );
    final local = ProjectWorkspaceSnapshot(
      manifest: base.manifest,
      boards: {'a': keepBoard, 'b': goneLocal},
      settings: base.settings,
    );
    final remote = ProjectWorkspaceSnapshot(
      manifest: const ProjectsManifest(
        projects: [keepEntry],
        updatedAt: 2,
        revision: 2,
      ),
      boards: {'a': keepBoard},
      settings: {'a': const ProjectSettings()},
    );

    final merged = mergeWorkspaces(local: local, remote: remote, base: base);
    expect(merged.manifest.projects.map((p) => p.id).toSet(), {'a', 'b'});
    final b = merged.manifest.projects.firstWhere((p) => p.id == 'b');
    expect(b.conflictDeleted, isTrue);
    expect(merged.boards['b']?.title, '本地板');
  });
}
