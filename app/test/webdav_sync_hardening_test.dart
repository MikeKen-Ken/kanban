import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/attachments/attachment_storage.dart';
import 'package:kanban/features/attachments/attachment_sync_adapter.dart';
import 'package:kanban/features/import_export/backup_archive_service.dart';
import 'package:kanban/features/import_export/backup_history_store.dart';
import 'package:kanban/features/project/project_settings.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/features/sync_conflict/sync_base_store.dart';
import 'package:kanban/features/trash/trash_models.dart';
import 'package:kanban/features/wallpapers/wallpaper_archive_service.dart';
import 'package:kanban/features/wallpapers/wallpaper_models.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:kanban/storage/kanban_paths.dart';
import 'package:kanban/webdav_sync/webdav_config.dart';
import 'package:kanban/webdav_sync/webdav_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockWebDavServer {
  _MockWebDavServer._(this._server);

  final HttpServer _server;
  final Map<String, Uint8List> files = {};
  final Set<String> dirs = {'/'};
  final List<({String method, String path})> requests = [];
  bool allowMove = true;
  bool sawMarkerDeleted = false;
  Future<void> Function(String method, String path)? onRequest;

  static Future<_MockWebDavServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _MockWebDavServer._(server);
    instance._listen();
    return instance;
  }

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  void _listen() {
    _server.listen((req) async {
      final path = _normalizePath(req.uri.path);
      requests.add((method: req.method, path: path));
      if (onRequest != null) {
        await onRequest!(req.method, path);
      }

      switch (req.method) {
        case 'OPTIONS':
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.set('DAV', '1, 2');
          await req.response.close();
          return;
        case 'MKCOL':
          final dirPath = path.endsWith('/') ? path : '$path/';
          if (dirs.contains(dirPath)) {
            req.response.statusCode = HttpStatus.methodNotAllowed;
          } else {
            dirs.add(dirPath);
            req.response.statusCode = HttpStatus.created;
          }
          await req.response.close();
          return;
        case 'PUT':
          final builder = BytesBuilder(copy: false);
          await for (final chunk in req) {
            builder.add(chunk);
          }
          files[path] = builder.takeBytes();
          req.response.statusCode = HttpStatus.created;
          await req.response.close();
          return;
        case 'GET':
          final bytes = files[path];
          if (bytes == null) {
            req.response.statusCode = HttpStatus.notFound;
          } else {
            req.response.statusCode = HttpStatus.ok;
            req.response.add(bytes);
          }
          await req.response.close();
          return;
        case 'DELETE':
          if (path.endsWith(KanbanPaths.liveWorkspaceMarkerFileName) ||
              path.endsWith(KanbanPaths.liveWallpapersMarkerFileName)) {
            sawMarkerDeleted = true;
          }
          if (files.remove(path) != null) {
            req.response.statusCode = HttpStatus.noContent;
          } else {
            final dirPath = path.endsWith('/') ? path : '$path/';
            if (dirs.remove(dirPath)) {
              req.response.statusCode = HttpStatus.noContent;
            } else {
              req.response.statusCode = HttpStatus.notFound;
            }
          }
          await req.response.close();
          return;
        case 'MOVE':
          if (!allowMove) {
            req.response.statusCode = HttpStatus.methodNotAllowed;
            await req.response.close();
            return;
          }
          final destHeader = req.headers.value('destination');
          if (destHeader == null) {
            req.response.statusCode = HttpStatus.badRequest;
            await req.response.close();
            return;
          }
          final destUri = Uri.parse(destHeader);
          final destPath = _normalizePath(destUri.path);
          final src = files.remove(path);
          if (src == null) {
            req.response.statusCode = HttpStatus.notFound;
          } else {
            files[destPath] = src;
            req.response.statusCode = HttpStatus.noContent;
          }
          await req.response.close();
          return;
        case 'PROPFIND':
          final existsFile = files[path];
          final dirPath = path.endsWith('/') ? path : '$path/';
          final existsDir = dirs.contains(dirPath) ||
              files.keys.any((k) => k.startsWith(dirPath));
          if (existsFile == null && !existsDir) {
            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
            return;
          }
          final responses = <String>[];
          if (existsFile != null) {
            responses.add(_propXml(path, isDir: false, size: existsFile.length));
          } else {
            responses.add(_propXml(dirPath, isDir: true));
            for (final entry in files.entries) {
              if (!entry.key.startsWith(dirPath)) continue;
              final rest = entry.key.substring(dirPath.length);
              if (rest.isEmpty || rest.contains('/')) continue;
              responses.add(
                _propXml(entry.key, isDir: false, size: entry.value.length),
              );
            }
          }
          req.response.statusCode = 207;
          req.response.headers.contentType =
              ContentType('application', 'xml', charset: 'utf-8');
          req.response.write(
            '<?xml version="1.0" encoding="utf-8"?>'
            '<d:multistatus xmlns:d="DAV:">${responses.join()}</d:multistatus>',
          );
          await req.response.close();
          return;
        default:
          req.response.statusCode = HttpStatus.methodNotAllowed;
          await req.response.close();
      }
    });
  }

  static String _normalizePath(String raw) {
    var path = Uri.decodeComponent(raw);
    if (!path.startsWith('/')) path = '/$path';
    if (path.length > 1 && path.endsWith('/')) {
      final without = path.substring(0, path.length - 1);
      if (without.contains('.')) return without;
    }
    return path;
  }

  static String _propXml(String href, {required bool isDir, int size = 0}) {
    final resourceType = isDir ? '<d:collection/>' : '';
    return '<d:response>'
        '<d:href>$href</d:href>'
        '<d:propstat><d:prop>'
        '<d:resourcetype>$resourceType</d:resourcetype>'
        '<d:getcontentlength>$size</d:getcontentlength>'
        '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
        '</d:response>';
  }

  Future<void> close() => _server.close(force: true);
}

WebDavConfig _configFor(
  String serverUrl, {
  String remotePath = '/KanbanApp',
  bool autoSync = false,
  int pollIntervalSeconds = 120,
  int pushDebounceSeconds = 5,
}) {
  return WebDavConfig(
    enabled: true,
    serverUrl: serverUrl,
    username: 'u',
    password: 'p',
    remotePath: remotePath,
    autoSync: autoSync,
    autoPull: autoSync,
    pollIntervalSeconds: pollIntervalSeconds,
    pushDebounceSeconds: pushDebounceSeconds,
  );
}

ProjectWorkspaceSnapshot _sampleWorkspace({
  String title = 'Board',
  List<CardAttachment> attachments = const [],
}) {
  final card = KanbanCard(
    id: 'c1',
    title: 'Task',
    order: 0,
    createdAt: 1,
    updatedAt: 1,
    attachments: attachments,
  );
  final board = KanbanBoard(
    id: 'p1',
    title: title,
    updatedAt: 1,
    revision: 1,
    columns: [
      KanbanColumn(id: 'todo', title: 'Todo', order: 0, cards: [card]),
    ],
  );
  return ProjectWorkspaceSnapshot(
    manifest: const ProjectsManifest(
      projects: [ProjectEntry(id: 'p1', title: 'Board', updatedAt: 1, revision: 1)],
      updatedAt: 1,
      revision: 1,
    ),
    boards: {'p1': board},
    settings: const {'p1': ProjectSettings()},
    projectTrash: const {'p1': TrashBin.empty},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousHttpOverrides = HttpOverrides.current;

  setUpAll(() {
    // 解除 Flutter 测试框架默认的 400 HTTP 拦截，以访问本机回环 Mock WebDAV 服务。
    HttpOverrides.global = null;
  });

  tearDownAll(() {
    HttpOverrides.global = previousHttpOverrides;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('上传实时归档不提前删 marker，MOVE 失败时也能安全回退覆盖', () async {
    final server = await _MockWebDavServer.start();
    addTearDown(server.close);
    server.allowMove = true;

    final prefs = await SharedPreferences.getInstance();
    final workspace = _sampleWorkspace();
    final service = WebDavSyncService(
      loadConfig: () async => _configFor(server.baseUrl),
      loadWorkspace: () async => workspace,
      saveWorkspace: (_) async {},
      syncBaseStore: SyncBaseStore(prefs),
    );
    addTearDown(service.dispose);

    await service.pushNow(force: true);
    expect(service.status, SyncStatus.success);
    expect(server.sawMarkerDeleted, isFalse);
    expect(
      server.files.containsKey('/KanbanApp/workspace.kanban-backup'),
      isTrue,
    );
    expect(
      server.files.containsKey('/KanbanApp/workspace.complete.json'),
      isTrue,
    );

    // 二次推送验证：即使 WebDAV 不支持 MOVE，也不得提前 DELETE marker，且不重复清理旧树
    server.allowMove = false;
    server.requests.clear();
    await service.pushNow(force: true);
    expect(service.status, SyncStatus.success);
    expect(server.sawMarkerDeleted, isFalse);
    expect(
      server.requests.where((r) => r.method == 'DELETE' && r.path.contains('projects.json')),
      isEmpty,
      reason: '已标记清理过的远端不应每次推送都发 7 次旧树清理请求',
    );
  });

  test('云端存在 archive 但缺少 marker 时报错，不得误判空库反推覆盖', () async {
    final server = await _MockWebDavServer.start();
    addTearDown(server.close);

    server.files['/KanbanApp/workspace.kanban-backup'] =
        Uint8List.fromList([1, 2, 3]);

    final prefs = await SharedPreferences.getInstance();
    final service = WebDavSyncService(
      loadConfig: () async => _configFor(server.baseUrl),
      loadWorkspace: () async => _sampleWorkspace(),
      saveWorkspace: (_) async {},
      syncBaseStore: SyncBaseStore(prefs),
    );
    addTearDown(service.dispose);

    await service.pullAndMerge(userInitiated: true);
    expect(service.status, SyncStatus.error);
    expect(
      server.files['/KanbanApp/workspace.kanban-backup'],
      Uint8List.fromList([1, 2, 3]),
      reason: '云端残包不应被本机覆写',
    );
  });

  test('knownSha 命中时跳过附件读盘与下载；若本机缺附件则补下载恢复', () async {
    final server = await _MockWebDavServer.start();
    addTearDown(server.close);
    final tempDir =
        await Directory.systemTemp.createTemp('kanban_lazy_attachment_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final store = createAttachmentStore(baseDirectory: tempDir)!;
    await store.writeBytes(
      projectId: 'p1',
      attachmentId: 'img1',
      bytes: Uint8List.fromList([9, 8, 7]),
    );
    final workspace = _sampleWorkspace(
      attachments: [
        CardAttachment(
          id: 'img1',
          fileName: 'a.jpg',
          mimeType: 'image/jpeg',
          order: 0,
          createdAt: 1,
        ),
      ],
    );
    final archiveBytes = const BackupArchiveService().encode(
      BackupPackage(
        workspace: workspace,
        attachments: {'attachments/p1/img1': Uint8List.fromList([9, 8, 7])},
      ),
    );
    server.files['/KanbanApp/workspace.kanban-backup'] = archiveBytes;
    server.files['/KanbanApp/workspace.complete.json'] = Uint8List.fromList(
      utf8.encode(
        jsonEncode(
          LiveArchiveMarker(
            id: KanbanPaths.liveWorkspaceArchiveId,
            sizeBytes: archiveBytes.length,
            sha256: LiveArchiveMarker.hashBytes(archiveBytes),
          ).toJson(),
        ),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    final syncBaseStore = SyncBaseStore(prefs);
    await syncBaseStore.save(
      workspace,
      remoteScope: SyncBaseStore.buildRemoteScope(
        serverUrl: server.baseUrl,
        remotePath: '/KanbanApp',
      ),
      labelTrash: const [],
    );
    await syncBaseStore.saveLiveWorkspaceSha256(
      LiveArchiveMarker.hashBytes(archiveBytes),
    );

    var fullPackageCaptureCount = 0;
    final service = WebDavSyncService(
      loadConfig: () async => _configFor(server.baseUrl),
      loadWorkspace: () async => workspace,
      saveWorkspace: (_) async {},
      syncBaseStore: syncBaseStore,
      attachmentSync: AttachmentSyncAdapter(store),
      captureBackupPackage: () async {
        fullPackageCaptureCount++;
        return BackupPackage(
          workspace: workspace,
          attachments: {'attachments/p1/img1': Uint8List.fromList([9, 8, 7])},
        );
      },
      applyBackupPackage: (pkg) async {
        final bytes = pkg.attachments['attachments/p1/img1'];
        if (bytes != null) {
          await store.writeBytes(
            projectId: 'p1',
            attachmentId: 'img1',
            bytes: bytes,
          );
        }
      },
    );
    addTearDown(service.dispose);

    // 1. 一致且附件存在：不应调用 captureBackupPackage，也不应下载 archive
    await service.pullAndMerge(userInitiated: true);
    expect(service.status, SyncStatus.success);
    expect(fullPackageCaptureCount, 0);
    expect(
      server.requests.where(
        (r) => r.method == 'GET' && r.path.endsWith('workspace.kanban-backup'),
      ),
      isEmpty,
    );

    // 2. 删除本地附件：应绕过短路并拉包恢复附件
    await store.deleteAttachment(projectId: 'p1', attachmentId: 'img1');
    expect(await store.existsImage(projectId: 'p1', attachmentId: 'img1'), isFalse);

    await service.pullAndMerge(userInitiated: true);
    expect(service.status, SyncStatus.success);
    expect(await store.existsImage(projectId: 'p1', attachmentId: 'img1'), isTrue);
  });

  test('SyncBaseStore 切换远端地址或路径时清空旧基线', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = SyncBaseStore(prefs);
    final ws = _sampleWorkspace();

    await store.save(
      ws,
      remoteScope: SyncBaseStore.buildRemoteScope(
        serverUrl: 'https://a.example/dav/',
        remotePath: '/KanbanApp',
      ),
      labelTrash: const [],
    );
    await store.saveLiveWorkspaceSha256('sha-a');
    await store.markLegacyTreeCleaned('https://a.example/dav|/KanbanApp');

    expect(
      await store.ensureRemoteScope(
        SyncBaseStore.buildRemoteScope(
          serverUrl: 'https://a.example/dav',
          remotePath: '/KanbanApp',
        ),
      ),
      isFalse,
    );
    expect(await store.load(), isNotNull);

    expect(
      await store.ensureRemoteScope(
        SyncBaseStore.buildRemoteScope(
          serverUrl: 'https://b.example/dav',
          remotePath: '/KanbanApp',
        ),
      ),
      isTrue,
    );
    expect(await store.load(), isNull);
    expect(store.loadLiveWorkspaceSha256(), isNull);
    expect(
      store.isLegacyTreeCleaned('https://a.example/dav|/KanbanApp'),
      isFalse,
    );
  });

  test('主同步进行中触发壁纸同步会排队而非静默丢弃', () async {
    final server = await _MockWebDavServer.start();
    addTearDown(server.close);

    final prefs = await SharedPreferences.getInstance();
    final gate = Completer<ProjectWorkspaceSnapshot>();
    var firstLoad = true;
    final ws = _sampleWorkspace();
    final service = WebDavSyncService(
      loadConfig: () async => _configFor(server.baseUrl),
      loadWorkspace: () {
        if (firstLoad) {
          firstLoad = false;
          return gate.future;
        }
        return Future.value(ws);
      },
      saveWorkspace: (_) async {},
      syncBaseStore: SyncBaseStore(prefs),
      captureWallpaperPackage: () async => const WallpaperArchivePackage(
        assets: [WallpaperAsset(id: 'w1', fileName: 'bg.jpg')],
      ),
    );
    addTearDown(service.dispose);

    final pushFuture = service.pushNow(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.status, SyncStatus.syncing);

    await service.uploadWallpapersNow();
    gate.complete(ws);
    await pushFuture;
    for (var i = 0;
        i < 50 &&
            (!server.files.containsKey('/KanbanApp/wallpapers.complete.json') ||
                service.status == SyncStatus.syncing);
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(service.status, SyncStatus.success);
    expect(
      server.files.containsKey('/KanbanApp/wallpapers.kanban-backup'),
      isTrue,
    );
    expect(
      server.files.containsKey('/KanbanApp/wallpapers.complete.json'),
      isTrue,
    );
  });

  test('BoardController.applyWallpaperPackage 元数据一致时不产生假 pendingUpload',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanban_wallpaper_apply_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
      backupHistoryStore: BackupHistoryStore(baseDirectory: tempDir),
    );
    addTearDown(controller.dispose);

    await controller.saveWebDavConfig(
      _configFor('https://127.0.0.1:1/dav'),
    );
    const asset = WallpaperAsset(id: 'w1', fileName: 'sky.jpg', updatedAt: 1);
    final package = WallpaperArchivePackage(
      assets: const [asset],
      files: {
        WallpaperArchiveService.originalPath('w1'): Uint8List.fromList([1, 2]),
        WallpaperArchiveService.thumbPath('w1'): Uint8List.fromList([3, 4]),
      },
    );

    // 模拟首次写入壁纸包并对齐 SyncBase
    await controller.applyWallpaperPackage(package);
    final syncBaseStore = SyncBaseStore(prefs);
    final snapshot =
        await controller.loadBoardSnapshot(controller.activeProjectId!);
    expect(snapshot, isNotNull);
    final repo = BoardRepository(
      prefs,
      BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
    final manifest = await repo.loadManifest();
    final settings = await repo.loadProjectSettings(controller.activeProjectId!);
    final shared = await repo.loadSharedContent();
    await syncBaseStore.save(
      ProjectWorkspaceSnapshot(
        manifest: manifest,
        boards: {controller.activeProjectId!: snapshot!},
        settings: {controller.activeProjectId!: settings},
        projectTrash: {controller.activeProjectId!: controller.activeProjectTrash},
        appTrash: controller.appTrash,
        sharedContent: shared,
      ),
      remoteScope: SyncBaseStore.buildRemoteScope(
        serverUrl: 'https://127.0.0.1:1/dav',
        remotePath: '/KanbanApp',
      ),
      labelTrash: controller.labelTrash,
    );

    // 二次应用元数据一致的壁纸包：不应递增 sharedContent.revision 或触发新的变更
    await controller.applyWallpaperPackage(package);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.sharedContent.revision, shared.revision);
    expect(controller.pendingSyncUploadCount, 0);
  });
}
