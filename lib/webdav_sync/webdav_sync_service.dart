import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:webdav_client/webdav_client.dart';

import '../models/kanban_models.dart';
import 'webdav_config.dart';

enum SyncStatus { idle, syncing, success, error }

/// 自动 WebDAV 同步：本地变更后防抖上传，启动/轮询时拉取合并
class WebDavSyncService {
  WebDavSyncService({
    required Future<WebDavConfig> Function() loadConfig,
    required Future<KanbanBoard> Function() loadBoard,
    required Future<void> Function(KanbanBoard board) saveBoard,
  })  : _loadConfig = loadConfig,
        _loadBoard = loadBoard,
        _saveBoard = saveBoard;

  final Future<WebDavConfig> Function() _loadConfig;
  final Future<KanbanBoard> Function() _loadBoard;
  final Future<void> Function(KanbanBoard board) _saveBoard;

  static const debounceDuration = Duration(milliseconds: 1500);

  SyncStatus status = SyncStatus.idle;
  String? lastError;
  DateTime? lastSyncedAt;

  Timer? _debounceTimer;
  Timer? _pollTimer;
  bool _pushInFlight = false;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  Client? _client(WebDavConfig config) {
    if (!config.isConfigured) return null;
    var url = config.serverUrl.trim();
    if (!url.endsWith('/')) url = '$url/';
    return newClient(
      url,
      user: config.username.trim(),
      password: config.password,
      debug: false,
    );
  }

  String _normalizeRemotePath(String path) {
    var p = path.trim();
    if (!p.startsWith('/')) p = '/$p';
    return p;
  }

  Future<void> _ensureParentDir(Client client, String remoteFilePath) async {
    final lastSlash = remoteFilePath.lastIndexOf('/');
    if (lastSlash <= 0) return;
    final dir = remoteFilePath.substring(0, lastSlash);
    try {
      await client.mkdirAll(dir);
    } catch (_) {
      // note: 目录已存在时忽略
    }
  }

  void _setStatus(SyncStatus value, {String? error}) {
    status = value;
    lastError = error;
    if (value == SyncStatus.success) {
      lastSyncedAt = DateTime.now();
    }
    _statusController.add(value);
  }

  /// 本地数据变更后调用 — 防抖自动上传，无需手动导出
  void schedulePush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      unawaited(pushNow());
    });
  }

  Future<void> pushNow() async {
    if (_pushInFlight) return;
    final config = await _loadConfig();
    if (!config.enabled || !config.autoSync || !config.isConfigured) return;

    final client = _client(config);
    if (client == null) return;

    _pushInFlight = true;
    _setStatus(SyncStatus.syncing);

    try {
      final board = await _loadBoard();
      final remotePath = _normalizeRemotePath(config.remotePath);
      await _ensureParentDir(client, remotePath);
      final bytes = Uint8List.fromList(utf8.encode(board.toJsonString()));
      await client.write(remotePath, bytes);
      _setStatus(SyncStatus.success);
    } catch (e) {
      _setStatus(SyncStatus.error, error: e.toString());
    } finally {
      _pushInFlight = false;
    }
  }

  Future<KanbanBoard?> pullRemote() async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return null;

    final client = _client(config);
    if (client == null) return null;

    final remotePath = _normalizeRemotePath(config.remotePath);
    try {
      await client.readProps(remotePath);
      final data = await client.read(remotePath);
      return KanbanBoard.fromJsonString(utf8.decode(data));
    } on Object catch (e) {
      // note: 远端文件不存在时返回 null，由调用方决定是否首次上传
      final message = e.toString().toLowerCase();
      if (message.contains('404') || message.contains('not found')) {
        return null;
      }
      _setStatus(SyncStatus.error, error: e.toString());
      rethrow;
    }
  }

  /// 启动时或手动刷新：拉取远端并与本地合并
  Future<void> pullAndMerge() async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;

    _setStatus(SyncStatus.syncing);
    try {
      final local = await _loadBoard();
      final remote = await pullRemote();
      if (remote == null) {
        await pushNow();
        return;
      }
      final merged = local.mergeWith(remote);
      await _saveBoard(merged);
      if (merged.revision > remote.revision ||
          (merged.revision == remote.revision &&
              merged.updatedAt > remote.updatedAt)) {
        await pushNow();
      } else {
        _setStatus(SyncStatus.success);
      }
    } catch (e) {
      _setStatus(SyncStatus.error, error: e.toString());
    }
  }

  Future<bool> testConnection(WebDavConfig config) async {
    final client = _client(config);
    if (client == null) return false;
    try {
      await client.ping();
      return true;
    } catch (_) {
      return false;
    }
  }

  void startPolling() {
    stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final config = await _loadConfig();
      if (!config.enabled || !config.autoSync) return;
      final interval = config.pollIntervalSeconds;
      final last = lastSyncedAt;
      if (last != null &&
          DateTime.now().difference(last).inSeconds < interval) {
        return;
      }
      await pullAndMerge();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void dispose() {
    _debounceTimer?.cancel();
    stopPolling();
    _statusController.close();
  }
}
