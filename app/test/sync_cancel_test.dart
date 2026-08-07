import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/features/sync_conflict/sync_base_store.dart';
import 'package:kanban/features/sync_conflict/workspace_snapshot.dart';
import 'package:kanban/webdav_sync/webdav_config.dart';
import 'package:kanban/webdav_sync/webdav_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

WebDavConfig _configured() => const WebDavConfig(
      enabled: true,
      serverUrl: 'https://example.invalid/dav',
      username: 'u',
      password: 'p',
      remotePath: '/KanbanApp',
      autoSync: true,
      autoPull: true,
      pollIntervalSeconds: 120,
      pushDebounceSeconds: 10,
    );

ProjectWorkspaceSnapshot _emptyWorkspace() => const ProjectWorkspaceSnapshot(
      manifest: ProjectsManifest(projects: [], updatedAt: 1, revision: 1),
      boards: {},
      settings: {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('空闲时取消同步返回 false', () async {
    final prefs = await SharedPreferences.getInstance();
    final service = WebDavSyncService(
      loadConfig: () async => _configured(),
      loadWorkspace: () async => _emptyWorkspace(),
      saveWorkspace: (_) async {},
      syncBaseStore: SyncBaseStore(prefs),
    );
    expect(service.cancelSync(), isFalse);
    expect(service.status, SyncStatus.idle);
    service.dispose();
  });

  test('同步进行中取消后恢复 idle，且可再次进入同步', () async {
    final prefs = await SharedPreferences.getInstance();
    Completer<ProjectWorkspaceSnapshot>? gate =
        Completer<ProjectWorkspaceSnapshot>();
    final service = WebDavSyncService(
      loadConfig: () async => _configured(),
      loadWorkspace: () => gate!.future,
      saveWorkspace: (_) async {},
      syncBaseStore: SyncBaseStore(prefs),
    );

    Future<void> waitUntilSyncing() async {
      for (var i = 0; i < 50; i++) {
        if (service.status == SyncStatus.syncing) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('未进入同步中状态');
    }

    final pull1 = service.pullAndMerge(userInitiated: true);
    await waitUntilSyncing();
    expect(service.cancelSync(), isTrue);
    expect(service.status, SyncStatus.idle);
    gate!.complete(_emptyWorkspace());
    await pull1;
    expect(service.status, SyncStatus.idle);

    gate = Completer<ProjectWorkspaceSnapshot>();
    final pull2 = service.pullAndMerge(userInitiated: true);
    await waitUntilSyncing();
    expect(service.cancelSync(), isTrue);
    expect(service.status, SyncStatus.idle);
    gate!.complete(_emptyWorkspace());
    await pull2;
    expect(service.status, SyncStatus.idle);

    service.dispose();
  });

  test('捕获本地快照进入工作区事务，网络等待不持锁', () async {
    final prefs = await SharedPreferences.getInstance();
    final gate = Completer<ProjectWorkspaceSnapshot>();
    var transactionActive = false;
    var loadedInsideTransaction = false;
    var sawNetworkWhileUnlocked = false;
    final service = WebDavSyncService(
      loadConfig: () async => _configured(),
      loadWorkspace: () {
        loadedInsideTransaction = transactionActive;
        return gate.future;
      },
      saveWorkspace: (_) async {},
      syncBaseStore: SyncBaseStore(prefs),
      runWorkspaceTransaction: <T>(action) async {
        transactionActive = true;
        try {
          return await action();
        } finally {
          transactionActive = false;
        }
      },
    );

    final pull = service.pullAndMerge(userInitiated: true);
    for (var i = 0; i < 50 && !loadedInsideTransaction; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(loadedInsideTransaction, isTrue);
    // 捕获仍在等待时事务应保持；完成后网络阶段（pullRemote）不持锁。
    expect(transactionActive, isTrue);

    service.cancelSync();
    gate.complete(_emptyWorkspace());
    await pull;
    // 取消后若曾进入远端拉取，事务应已释放。
    expect(transactionActive, isFalse);
    sawNetworkWhileUnlocked = !transactionActive;
    expect(sawNetworkWhileUnlocked, isTrue);
    service.dispose();
  });
}
