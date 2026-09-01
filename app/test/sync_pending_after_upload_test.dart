import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/activity/activity_models.dart';
import 'package:kanban/features/project/project_settings.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/features/shared_content/shared_content.dart';
import 'package:kanban/features/sync_conflict/sync_base_store.dart';
import 'package:kanban/features/trash/trash_models.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:kanban/webdav_sync/webdav_config.dart';
import 'package:kanban/webdav_sync/webdav_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProjectWorkspaceSnapshot> _loadWorkspace(BoardRepository repo) async {
  final manifest = await repo.loadManifest();
  final boards = <String, KanbanBoard>{};
  final settings = <String, ProjectSettings>{};
  final projectTrash = <String, TrashBin>{};
  for (final entry in manifest.projects) {
    if (await repo.storage.hasProjectBoard(entry.id)) {
      boards[entry.id] = await repo.loadBoard(entry.id);
    }
    settings[entry.id] = await repo.loadProjectSettings(entry.id);
    projectTrash[entry.id] = await repo.loadProjectTrash(entry.id);
  }
  return ProjectWorkspaceSnapshot(
    manifest: manifest,
    boards: boards,
    settings: settings,
    projectTrash: projectTrash,
    appTrash: await repo.loadAppTrash(),
    sharedContent: await repo.loadSharedContent(),
  );
}

class _DelayingSyncBaseStore extends SyncBaseStore {
  _DelayingSyncBaseStore(super.prefs);

  Completer<void>? delayAfterLoad;
  final enteredLoad = Completer<void>();

  @override
  Future<ProjectWorkspaceSnapshot?> load() async {
    final snapshot = await super.load();
    if (!enteredLoad.isCompleted) enteredLoad.complete();
    final delay = delayAfterLoad;
    if (delay != null) await delay.future;
    return snapshot;
  }
}

WebDavConfig _configured() => const WebDavConfig(
      enabled: true,
      serverUrl: 'https://example.invalid/dav',
      username: 'u',
      password: 'p',
      remotePath: '/KanbanApp',
      autoSync: false,
      autoPull: false,
      pollIntervalSeconds: 120,
      pushDebounceSeconds: 5,
    );

String _pendingReason({
  required ProjectWorkspaceSnapshot workspace,
  required ProjectWorkspaceSnapshot? baseline,
}) {
  if (baseline == null) return 'SyncBase is null';
  final plan = buildSyncUploadPlan(workspace: workspace, baseline: baseline);
  if (plan.items.isEmpty) return 'no pending items';
  return plan.items.map((item) => item.label).join(', ');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认工作区经 SyncBase JSON 往返后 pending 为 0', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanban_pending_roundtrip_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = BoardRepository(
      prefs,
      BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
    await repo.ensureInitialized();

    final snapshot = await _loadWorkspace(repo);
    final encoded = jsonDecode(jsonEncode(snapshot.toJson()))
        as Map<String, dynamic>;
    final baseline = ProjectWorkspaceSnapshot.fromJson(encoded);

    expect(
      countPendingLiveArchiveUploads(
        workspace: snapshot,
        baseline: baseline,
      ),
      0,
      reason: _pendingReason(workspace: snapshot, baseline: baseline),
    );
  });

  test('上传成功写入 SyncBase 后 refreshPendingUploadCount 为 0', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanban_pending_refresh_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = BoardRepository(
      prefs,
      BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
    await repo.ensureInitialized();

    final uploaded = await _loadWorkspace(repo);
    final store = SyncBaseStore(prefs);
    await store.save(uploaded);

    final service = WebDavSyncService(
      loadConfig: () async => const WebDavConfig(
        enabled: true,
        serverUrl: 'https://example.invalid/dav',
        username: 'u',
        password: 'p',
        remotePath: '/KanbanApp',
        autoSync: false,
        autoPull: false,
        pollIntervalSeconds: 120,
        pushDebounceSeconds: 5,
      ),
      loadWorkspace: () => _loadWorkspace(repo),
      saveWorkspace: (_) async {},
      syncBaseStore: store,
    );
    addTearDown(service.dispose);
    service.pendingUploadCount = 1;

    final count = await service.refreshPendingUploadCount();
    final latest = await _loadWorkspace(repo);
    final baseline = await store.load();
    expect(
      count,
      0,
      reason: _pendingReason(workspace: latest, baseline: baseline),
    );
  });

  test('含活动历史的工作区上传后 pending 为 0', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanban_pending_activity_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = BoardRepository(
      prefs,
      BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
    await repo.ensureInitialized();
    final manifest = await repo.loadManifest();
    final projectId = manifest.projects.first.id;
    await repo.saveSharedContent(
      SharedContent(
        activityByProject: {
          projectId: ActivityLog(
            events: [
              for (var i = 63; i >= 0; i--)
                ActivityEvent(
                  id: 'e-${i.toString().padLeft(2, '0')}',
                  projectId: projectId,
                  entityType: 'card',
                  entityId: 'c1',
                  entityTitle: 'A',
                  action: ActivityAction.updated,
                  occurredAt: 100,
                ),
            ],
          ),
        },
        revision: 1,
        updatedAt: 1,
      ),
    );
    final board = await repo.loadBoard(projectId);
    await repo.saveBoard(
      projectId,
      board.copyWith(
        columns: [
          for (final column in board.columns)
            if (column.id == 'todo')
              column.copyWith(
                cards: [
                  KanbanCard(
                    id: 'c1',
                    title: 'Task',
                    order: 0,
                    createdAt: 1,
                    updatedAt: 1,
                  ),
                ],
              )
            else
              column,
        ],
        revision: board.revision + 1,
      ),
    );

    final uploaded = await _loadWorkspace(repo);
    final store = SyncBaseStore(prefs);
    await store.save(uploaded);
    final latest = await _loadWorkspace(repo);
    final baseline = await store.load();
    expect(
      countPendingLiveArchiveUploads(
        workspace: latest,
        baseline: baseline,
      ),
      0,
      reason: _pendingReason(workspace: latest, baseline: baseline),
    );
  });

  test('上传成功后，旧的 pending 刷新不得把 0 盖回 1', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final snapshot = ProjectWorkspaceSnapshot(
      manifest: const ProjectsManifest(
        projects: const [
          ProjectEntry(id: 'p1', title: '甲', updatedAt: 1, revision: 1),
        ],
        updatedAt: 1,
        revision: 1,
      ),
      boards: {
        'p1': KanbanBoard.empty(id: 'p1', title: '甲'),
      },
      settings: const {'p1': ProjectSettings()},
      projectTrash: const {'p1': TrashBin.empty},
    );
    final store = _DelayingSyncBaseStore(prefs);
    final service = WebDavSyncService(
      loadConfig: () async => _configured(),
      loadWorkspace: () async => snapshot,
      saveWorkspace: (_) async {},
      syncBaseStore: store,
    );
    addTearDown(service.dispose);
    service.pendingUploadCount = 1;

    final staleGate = Completer<void>();
    store.delayAfterLoad = staleGate;
    final stale = service.refreshPendingUploadCount();
    await store.enteredLoad.future;
    expect(staleGate.isCompleted, isFalse);

    await store.save(snapshot);
    store.delayAfterLoad = null;
    expect(await service.refreshPendingUploadCount(), 0);

    staleGate.complete();
    expect(await stale, 0, reason: '过期刷新仍按旧 SyncBase 算出 1 pending');
    expect(service.pendingUploadCount, 0);
  });
}
