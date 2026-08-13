import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/features/sync_conflict/sync_base_store.dart';
import 'package:kanban/features/sync_conflict/workspace_snapshot.dart';
import 'package:kanban/webdav_sync/webdav_config.dart';
import 'package:kanban/webdav_sync/webdav_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

WebDavConfig _configured({
  bool autoSync = true,
  bool autoPull = true,
}) =>
    WebDavConfig(
      enabled: true,
      serverUrl: 'https://example.invalid/dav',
      username: 'u',
      password: 'p',
      remotePath: '/KanbanApp',
      autoSync: autoSync,
      autoPull: autoPull,
      pollIntervalSeconds: 120,
      pushDebounceSeconds: 5,
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

  Future<WebDavSyncService> _service(WebDavConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    return WebDavSyncService(
      loadConfig: () async => config,
      loadWorkspace: () async => _emptyWorkspace(),
      saveWorkspace: (_) async {},
      syncBaseStore: SyncBaseStore(prefs),
    );
  }

  test('schedulePush 不会自动进入同步', () async {
    final service = await _service(_configured());
    service.schedulePush();
    await Future<void>.delayed(Duration.zero);
    expect(service.status, SyncStatus.idle);
    service.dispose();
  });

  test('pushNow 非 force 不会上传', () async {
    final service = await _service(_configured());
    await service.pushNow();
    expect(service.status, SyncStatus.idle);
    service.dispose();
  });

  test('非用户发起的 pullAndMerge 不会拉取', () async {
    final service = await _service(_configured());
    await service.pullAndMerge();
    expect(service.status, SyncStatus.idle);
    service.dispose();
  });

  test('startPolling 不会后台拉取', () async {
    final service = await _service(_configured());
    service.startPolling();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.status, SyncStatus.idle);
    service.dispose();
  });
}
