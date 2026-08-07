import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/project/project_settings.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/features/shared_content/shared_content.dart';
import 'package:kanban/features/sync_conflict/workspace_snapshot.dart';
import 'package:kanban/features/trash/trash_models.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/webdav_sync/sync_index.dart';

KanbanCard _card(String id) => KanbanCard(
      id: id,
      title: '卡',
      order: 0,
      createdAt: 1,
      updatedAt: 1,
    );

KanbanColumn _column(String id) => KanbanColumn(
      id: id,
      title: '列',
      order: 0,
      cards: [_card('c-$id')],
    );

KanbanBoard _board(String id) => KanbanBoard(
      id: id,
      title: '看板',
      columns: [_column('col-a'), _column('col-b')],
      updatedAt: 1,
      revision: 1,
    );

ProjectWorkspaceSnapshot _workspace(String projectId) {
  return ProjectWorkspaceSnapshot(
    manifest: ProjectsManifest(
      projects: [
        ProjectEntry(
          id: projectId,
          title: '项目',
          updatedAt: 1,
          revision: 1,
        ),
      ],
      updatedAt: 1,
      revision: 1,
    ),
    boards: {projectId: _board(projectId)},
    settings: {projectId: const ProjectSettings()},
    projectTrash: {projectId: TrashBin.empty},
    sharedContent: SharedContent.empty,
  );
}

void main() {
  test('同一工作区指纹稳定且可匹配', () {
    final ws = _workspace('p1');
    final index = buildSyncIndex(ws, updatedAt: 100);
    expect(index.isSupportedSchema, isTrue);
    expect(syncIndexMatchesWorkspace(index, ws), isTrue);
    expect(
      index.files.containsKey(SyncIndexPaths.projectBoard('p1')),
      isTrue,
    );
    expect(
      index.files.containsKey(SyncIndexPaths.projectColumn('p1', 'col-a')),
      isTrue,
    );
  });

  test('改动一列后索引不再整体匹配，仅该列不可复用', () {
    final base = _workspace('p1');
    final index = buildSyncIndex(base, updatedAt: 1);

    final changedBoard = KanbanBoard(
      id: 'p1',
      title: '看板',
      columns: [
        _column('col-a'),
        KanbanColumn(
          id: 'col-b',
          title: '列已改',
          order: 0,
          cards: [_card('c-col-b')],
        ),
      ],
      updatedAt: 2,
      revision: 2,
    );
    final changed = ProjectWorkspaceSnapshot(
      manifest: base.manifest,
      boards: {'p1': changedBoard},
      settings: base.settings,
      projectTrash: base.projectTrash,
      sharedContent: base.sharedContent,
    );

    expect(syncIndexMatchesWorkspace(index, changed), isFalse);
    expect(
      canReuseSyncBaseJson(
        remoteIndex: index,
        relativePath: SyncIndexPaths.projectColumn('p1', 'col-a'),
        baseJson: base.boards['p1']!.columns.first.toJson(),
      ),
      isTrue,
    );
    expect(
      canReuseSyncBaseJson(
        remoteIndex: index,
        relativePath: SyncIndexPaths.projectColumn('p1', 'col-b'),
        baseJson: changedBoard.columns[1].toJson(),
      ),
      isFalse,
    );
  });

  test('无索引或 schema 不支持时不可复用', () {
    final ws = _workspace('p1');
    expect(
      canReuseSyncBaseJson(
        remoteIndex: null,
        relativePath: SyncIndexPaths.projects,
        baseJson: ws.manifest.toJson(),
      ),
      isFalse,
    );
    final bad = SyncIndex(
      schemaVersion: 99,
      updatedAt: 1,
      files: buildSyncIndexFiles(ws),
    );
    expect(bad.isSupportedSchema, isFalse);
    expect(syncIndexMatchesWorkspace(bad, ws), isFalse);
  });

  test('fromJson 往返', () {
    final ws = _workspace('p1');
    final index = buildSyncIndex(ws, updatedAt: 42);
    final roundTrip = SyncIndex.fromJson(index.toJson());
    expect(roundTrip.updatedAt, 42);
    expect(roundTrip.files, index.files);
    expect(syncIndexMatchesWorkspace(roundTrip, ws), isTrue);
  });
}
