part of 'webdav_sync_service.dart';

mixin _WebDavSyncClientIo on _WebDavSyncHost, _WebDavSyncScheduler {
  /// 合并同路径 `mkdirAll`，避免并行上传时第二个请求在目录建完前就 PUT。
  final Map<String, Future<void>> _ensureDirInflight = {};

  void _resetEnsuredRemoteDirs() {
    _ensureDirInflight.clear();
  }

  Future<void> _ensureRemoteDir(Client client, String dir) {
    if (dir.isEmpty) return Future<void>.value();
    return _ensureDirInflight.putIfAbsent(dir, () async {
      try {
        await client.mkdirAll(dir);
      } catch (_) {
        // note: 目录已存在时忽略
      }
    });
  }

  Client? _client(WebDavConfig config) {
    if (!config.isConfigured) return null;
    var url = config.serverUrl.trim();
    if (!url.endsWith('/')) url = '$url/';
    final client = newClient(
      url,
      user: config.username.trim(),
      password: config.password,
      debug: false,
    );
    // note: 图片附件可能较大，放宽传输超时避免拉取被误判为失败
    client.setReceiveTimeout(120000);
    client.setSendTimeout(120000);
    return client;
  }

  bool _isRemoteNotFound(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('404') ||
        message.contains('not found') ||
        message.contains('no such file') ||
        message.contains('不存在');
  }

  Iterable<String> _directoryPathCandidates(String dir) sync* {
    yield dir;
    if (!dir.endsWith('/')) yield '$dir/';
  }

  Future<List<File>> _readDirWithFallback(Client client, String dir) async {
    _ensureNotCancelled();
    for (final path in _directoryPathCandidates(dir)) {
      _ensureNotCancelled();
      try {
        return await client.readDir(path);
      } catch (_) {
        continue;
      }
    }
    return const [];
  }

  String _remoteFilePath(String parentDir, File file) {
    final path = file.path?.trim();
    if (path != null && path.isNotEmpty) {
      final normalized = _normalizeRemotePath(path, parentDir);
      if (normalized != null) return normalized;
    }
    final name = file.name?.trim();
    if (name != null && name.isNotEmpty) {
      final prefix = parentDir.endsWith('/') ? parentDir : '$parentDir/';
      return '$prefix$name';
    }
    return parentDir;
  }

  /// 将 PROPFIND 返回的绝对 href（如 /dav/Koofr/KanbanApp/...）收成客户端相对路径
  String? _normalizeRemotePath(String path, String parentDir) {
    if (path.startsWith(parentDir)) return path;
    // note: Koofr 等会返回带挂载前缀的 href；截到与 parentDir 相同的后缀
    final marker = parentDir.startsWith('/') ? parentDir : '/$parentDir';
    final index = path.indexOf(marker);
    if (index >= 0) {
      return path.substring(index);
    }
    if (path.startsWith('/')) return path;
    final prefix = parentDir.endsWith('/') ? parentDir : '$parentDir/';
    return '$prefix$path';
  }

  String _remoteBase(WebDavConfig config) =>
      KanbanPaths.remoteBaseDir(config.remotePath);

  Future<void> _ensureParentDir(Client client, String remoteFilePath) async {
    final lastSlash = remoteFilePath.lastIndexOf('/');
    if (lastSlash <= 0) return;
    await _ensureRemoteDir(client, remoteFilePath.substring(0, lastSlash));
  }
  Future<void> _writeJson(Client client, String path, Object data) async {
    _ensureNotCancelled();
    await _ensureParentDir(client, path);
    _ensureNotCancelled();
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );
    await client.write(path, bytes);
  }

  Future<Map<String, dynamic>?> _readJson(
    Client client,
    String path,
  ) async {
    _ensureNotCancelled();
    try {
      final data = await client.read(path);
      _ensureNotCancelled();
      final json = tryDecodeJsonBytes(data, path: path);
      if (json != null) return json;
      // note: 远端个别文件损坏时不拖垮整次同步；由调用方处理 null
      return null;
    } on SyncCancelledException {
      rethrow;
    } on Object catch (e) {
      if (_isRemoteNotFound(e)) {
        return null;
      }
      if (e is FormatException) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> _writeBytes(Client client, String path, Uint8List bytes) async {
    _ensureNotCancelled();
    await _ensureParentDir(client, path);
    // note: webdav_client.write() 会把字节拆成「每字节一个 chunk」的 Stream，
    // 截图 JPEG 体积稍大时极易超时；改走临时文件 + writeFromFile（按块流式上传）。
    final tmp = io.File(
      '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}'
      'kanban_webdav_${DateTime.now().microsecondsSinceEpoch}.bin',
    );
    try {
      _ensureNotCancelled();
      await tmp.writeAsBytes(bytes, flush: true);
      _ensureNotCancelled();
      await client.writeFromFile(tmp.path, path);
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {
        // note: 临时文件清理失败可忽略
      }
    }
  }

  Future<void> _writeBytesWithRetry(
    Client client,
    String path,
    Uint8List bytes,
  ) async {
    try {
      await _writeBytes(client, path, bytes);
    } on SyncCancelledException {
      rethrow;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _ensureNotCancelled();
      await _writeBytes(client, path, bytes);
    }
  }

  Future<Uint8List?> _readBytes(Client client, String path) async {
    _ensureNotCancelled();
    try {
      final data = await client.read(path);
      _ensureNotCancelled();
      return Uint8List.fromList(data);
    } on SyncCancelledException {
      rethrow;
    } on Object catch (e) {
      if (_isRemoteNotFound(e)) {
        return null;
      }
      rethrow;
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
}
