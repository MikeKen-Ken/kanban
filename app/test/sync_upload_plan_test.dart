import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/project/project_settings.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/features/shared_content/shared_content.dart';
import 'package:kanban/features/sync_conflict/workspace_snapshot.dart';
import 'package:kanban/features/trash/trash_models.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/webdav_sync/sync_upload_plan.dart';

KanbanCard _card(String id, {String title = '卡', int updatedAt = 1}) {
  return KanbanCard(
    id: id,
    title: title,
    order: 0,
    createdAt: 1,
    updatedAt: updatedAt,
  );
}

KanbanColumn _column(
  String id, {
  String title = '列',
  List<KanbanCard>? cards,
}) {
  return KanbanColumn(
    id: id,
    title: title,
    order: 0,
    cards: cards ?? [_card('c-$id')],
  );
}

KanbanBoard _board(
  String id, {
  String title = '看板',
  List<KanbanColumn>? columns,
  int revision = 1,
}) {
  return KanbanBoard(
    id: id,
    title: title,
    columns: columns ?? [_column('col-a'), _column('col-b')],
    updatedAt: 1,
    revision: revision,
  );
}

ProjectWorkspaceSnapshot _workspace({
  required List<ProjectEntry> projects,
  required Map<String, KanbanBoard> boards,
  Map<String, ProjectSettings>? settings,
  SharedContent sharedContent = SharedContent.empty,
}) {
  return ProjectWorkspaceSnapshot(
    manifest: ProjectsManifest(
      projects: projects,
      updatedAt: 1,
      revision: 1,
    ),
    boards: boards,
    settings: {
      for (final p in projects)
        p.id: settings?[p.id] ?? const ProjectSettings(),
    },
    projectTrash: {
      for (final p in projects) p.id: TrashBin.empty,
    },
    sharedContent: sharedContent,
  );
}

ProjectEntry _entry(String id, {String title = '项目'}) => ProjectEntry(
      id: id,
      title: title,
      updatedAt: 1,
      revision: 1,
    );

void main() {
  test('无基线时生成全量上传计划', () {
    final workspace = _workspace(
      projects: [_entry('p1', title: '甲'), _entry('p2', title: '乙')],
      boards: {
        'p1': _board('p1', title: '甲'),
        'p2': _board('p2', title: '乙'),
      },
    );

    final plan = buildSyncUploadPlan(workspace: workspace, baseline: null);

    expect(plan.skippedFileCount, 0);
    expect(plan.needsProjectCleanup, isTrue);
    expect(plan.projectsNeedingColumnCleanup, {'p1', 'p2'});
    expect(
      plan.items.where((i) => i.kind == SyncUploadKind.column).length,
      4,
    );
    expect(
      plan.items.any((i) => i.kind == SyncUploadKind.projectsManifest),
      isTrue,
    );
  });

  test('未变更项目相对 SyncBase 完全跳过', () {
    final base = _workspace(
      projects: [_entry('p1', title: '甲'), _entry('p2', title: '乙')],
      boards: {
        'p1': _board('p1', title: '甲'),
        'p2': _board('p2', title: '乙'),
      },
      sharedContent: const SharedContent(
        labels: [],
        savedViews: [],
        cardTemplates: [],
        activityByProject: {},
        updatedAt: 1,
        revision: 1,
      ),
    );
    final local = _workspace(
      projects: [_entry('p1', title: '甲'), _entry('p2', title: '乙')],
      boards: {
        'p1': _board('p1', title: '甲'),
        'p2': _board('p2', title: '乙'),
      },
      sharedContent: const SharedContent(
        labels: [],
        savedViews: [],
        cardTemplates: [],
        activityByProject: {},
        updatedAt: 1,
        revision: 1,
      ),
    );

    final plan = buildSyncUploadPlan(workspace: local, baseline: base);

    expect(plan.items, isEmpty);
    expect(plan.skippedFileCount, greaterThan(0));
    expect(plan.needsProjectCleanup, isFalse);
    expect(plan.projectsNeedingColumnCleanup, isEmpty);
    expect(countPendingSyncUploads(workspace: local, baseline: base), 0);
  });

  test('壁纸轮播位置变化不产生同步上传', () {
    final base = _workspace(
      projects: [_entry('p1')],
      boards: {'p1': _board('p1')},
      settings: {
        'p1': const ProjectSettings(
          wallpaperIds: ['wall-a', 'wall-b'],
          wallpaperActiveId: 'wall-a',
        ),
      },
    );
    final local = _workspace(
      projects: [_entry('p1')],
      boards: {'p1': _board('p1')},
      settings: {
        'p1': const ProjectSettings(
          wallpaperIds: ['wall-a', 'wall-b'],
          wallpaperActiveId: 'wall-b',
        ),
      },
    );

    final plan = buildSyncUploadPlan(workspace: local, baseline: base);

    expect(plan.items, isEmpty);
    expect(countPendingSyncUploads(workspace: local, baseline: base), 0);
  });

  test('只改一张卡时只上传该列与变更的看板元数据', () {
    final baseBoard = _board(
      'p1',
      title: '甲',
      columns: [
        _column('todo', title: '待办', cards: [_card('c1', title: '旧')]),
        _column('done', title: '完成', cards: [_card('c2')]),
      ],
      revision: 1,
    );
    final nextBoard = _board(
      'p1',
      title: '甲',
      columns: [
        _column('todo', title: '待办', cards: [_card('c1', title: '新', updatedAt: 2)]),
        _column('done', title: '完成', cards: [_card('c2')]),
      ],
      revision: 2,
    );
    final base = _workspace(
      projects: [_entry('p1', title: '甲'), _entry('p2', title: '乙')],
      boards: {
        'p1': baseBoard,
        'p2': _board('p2', title: '乙'),
      },
    );
    final local = _workspace(
      projects: [_entry('p1', title: '甲'), _entry('p2', title: '乙')],
      boards: {
        'p1': nextBoard,
        'p2': _board('p2', title: '乙'),
      },
    );

    final plan = buildSyncUploadPlan(workspace: local, baseline: base);
    final kinds = plan.items.map((i) => i.kind).toSet();
    final columnIds = plan.items
        .where((i) => i.kind == SyncUploadKind.column)
        .map((i) => i.columnId)
        .toSet();

    expect(syncUploadPlanTouchedProjectIds(plan), {'p1'});
    expect(columnIds, {'todo'});
    expect(kinds.contains(SyncUploadKind.boardMetadata), isTrue);
    expect(kinds.contains(SyncUploadKind.settings), isFalse);
    expect(
      plan.items.any((i) => i.projectId == 'p2'),
      isFalse,
    );
    expect(
      countPendingSyncUploads(workspace: local, baseline: base),
      plan.items.length,
    );
  });

  test('删除列时标记列清理且不上传已删列', () {
    final base = _workspace(
      projects: [_entry('p1')],
      boards: {
        'p1': _board(
          'p1',
          columns: [_column('a'), _column('b')],
        ),
      },
    );
    final local = _workspace(
      projects: [_entry('p1')],
      boards: {
        'p1': _board(
          'p1',
          columns: [_column('a')],
          revision: 2,
        ),
      },
    );

    final plan = buildSyncUploadPlan(workspace: local, baseline: base);
    expect(plan.projectsNeedingColumnCleanup, {'p1'});
    expect(
      plan.items.where((i) => i.kind == SyncUploadKind.column),
      isEmpty,
      reason: '未改列不应上传；远端孤儿列靠 cleanup 删除',
    );
    expect(
      plan.items.any((i) => i.kind == SyncUploadKind.boardMetadata),
      isTrue,
    );
  });

  test('上传后本机无文件差异则不排队再推', () {
    final uploaded = _workspace(
      projects: [_entry('p1')],
      boards: {
        'p1': _board('p1'),
      },
    );
    expect(
      shouldQueueFollowUpPushAfterUpload(
        uploaded: uploaded,
        latest: uploaded,
      ),
      isFalse,
    );
  });

  test('上传后仅新增本地列才排队增量推送，未改文件不算差异', () {
    final uploaded = _workspace(
      projects: [_entry('p1')],
      boards: {
        'p1': _board(
          'p1',
          columns: [_column('a'), _column('b')],
        ),
      },
    );
    final latest = _workspace(
      projects: [_entry('p1')],
      boards: {
        'p1': _board(
          'p1',
          columns: [_column('a'), _column('b'), _column('c')],
          revision: 2,
        ),
      },
    );
    expect(
      shouldQueueFollowUpPushAfterUpload(
        uploaded: uploaded,
        latest: latest,
      ),
      isTrue,
    );
    expect(
      countPendingSyncUploads(workspace: latest, baseline: uploaded),
      2,
      reason: '看板元数据 + 新列，不应把未改的 a/b 列算进去',
    );
    expect(
      countPendingLiveArchiveUploads(workspace: latest, baseline: uploaded),
      1,
    );
    expect(
      countPendingLiveArchiveUploads(workspace: uploaded, baseline: uploaded),
      0,
    );
  });
}
