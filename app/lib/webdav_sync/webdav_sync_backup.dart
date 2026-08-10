part of 'webdav_sync_service.dart';

mixin _WebDavSyncBackup on _WebDavSyncHost, _WebDavSyncClientIo {
  /// 将本地时间点备份镜像到 WebDAV；未启用 WebDAV 时仅保留本地副本。
  Future<void> writeBackupSnapshot(
    BackupSnapshotInfo snapshot,
    Uint8List bytes,
  ) {
    return _backupMutex.guard(() async {
      final config = await _loadConfig();
      if (!config.enabled || !config.isConfigured) return;
      final client = _client(config);
      if (client == null) return;
      final base = _remoteBase(config);
      final backupDir = KanbanPaths.remoteBackupDir(base, snapshot.id);
      final archivePath =
          KanbanPaths.remoteBackupArchivePath(base, snapshot.id);
      final markerPath = KanbanPaths.remoteBackupMarkerPath(base, snapshot.id);
      await client.mkdirAll(backupDir);
      try {
        await client.remove(markerPath);
      } catch (_) {
        // 不存在完成标记时继续上传。
      }
      final temporary = io.File(
        '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}'
        'kanban_backup_${snapshot.id}.bin',
      );
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await client.writeFromFile(temporary.path, archivePath);
        final checksum = sha256.convert(bytes).toString();
        final markerBytes = Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'id': snapshot.id,
              'createdAt': snapshot.createdAt.toUtc().toIso8601String(),
              'sizeBytes': bytes.length,
              'sha256': checksum,
            }),
          ),
        );
        // 完成标记最后写入；没有标记的中断上传不会出现在恢复列表。
        await client.write(markerPath, markerBytes);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
  }

  /// 列出远端时间点备份。
  ///
  /// 不占用 [_backupMutex]，避免上传/清理进行中时设置页永久等待列表。
  /// 未写完完成标记的目录会被跳过，与上传并发时结果仍安全。
  Future<List<BackupSnapshotInfo>> listRemoteBackupSnapshots() async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return const [];
    final client = _client(config);
    if (client == null) return const [];
    final directory = KanbanPaths.remoteBackupsDir(_remoteBase(config));
    final result = <BackupSnapshotInfo>[];
    List<File> entries;
    try {
      entries = await client.readDir(directory);
    } catch (error) {
      if (_isRemoteNotFound(error)) return const [];
      rethrow;
    }
    for (final file in entries) {
      if (file.isDir != true) continue;
      final name = file.name ?? file.path?.split('/').last ?? '';
      final id = name;
      if (!_isSafeBackupId(id)) continue;
      final timestamp = int.tryParse(id.split('-').first);
      if (timestamp == null) continue;
      try {
        final markerBytes = await client.read(
          KanbanPaths.remoteBackupMarkerPath(_remoteBase(config), id),
        );
        final marker = tryDecodeJsonBytes(markerBytes);
        if (marker == null || marker['id'] != id) continue;
        result.add(
          BackupSnapshotInfo(
            id: id,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              timestamp,
              isUtc: true,
            ),
            sizeBytes: (marker['sizeBytes'] as num?)?.toInt() ?? 0,
          ),
        );
      } catch (error) {
        if (_isRemoteNotFound(error)) continue;
        rethrow;
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<Uint8List?> readRemoteBackupSnapshot(String id) {
    return _backupMutex.guard(() async {
      if (!_isSafeBackupId(id)) throw const FormatException('备份标识无效');
      final config = await _loadConfig();
      if (!config.enabled || !config.isConfigured) return null;
      final client = _client(config);
      if (client == null) return null;
      final base = _remoteBase(config);
      final markerPath = KanbanPaths.remoteBackupMarkerPath(base, id);
      final markerBytes = await client.read(markerPath);
      final marker = tryDecodeJsonBytes(markerBytes);
      if (marker == null || marker['id'] != id) return null;
      final bytes = Uint8List.fromList(
        await client.read(KanbanPaths.remoteBackupArchivePath(base, id)),
      );
      final expectedSize = (marker['sizeBytes'] as num?)?.toInt();
      final expectedHash = marker['sha256'] as String?;
      if (expectedSize != bytes.length ||
          expectedHash == null ||
          sha256.convert(bytes).toString() != expectedHash) {
        try {
          await client.remove(markerPath);
        } catch (_) {
          // 移除失败时仍报告校验错误。
        }
        throw const FormatException('WebDAV 备份校验失败');
      }
      return bytes;
    });
  }

  Future<void> deleteRemoteBackupsOlderThan(DateTime cutoff) {
    return _backupMutex.guard(() async {
      final config = await _loadConfig();
      if (!config.enabled || !config.isConfigured) return;
      final client = _client(config);
      if (client == null) return;
      final directory = KanbanPaths.remoteBackupsDir(_remoteBase(config));
      List<File> entries;
      try {
        entries = await client.readDir(directory);
      } catch (error) {
        if (_isRemoteNotFound(error)) return;
        rethrow;
      }
      for (final file in entries) {
        if (file.isDir != true) continue;
        final name = file.name ?? file.path?.split('/').last ?? '';
        final id = name;
        if (!_isSafeBackupId(id)) continue;
        final timestamp = int.tryParse(id.split('-').first);
        if (timestamp == null) continue;
        final createdAt = DateTime.fromMillisecondsSinceEpoch(
          timestamp,
          isUtc: true,
        );
        if (!createdAt.isBefore(cutoff.toUtc())) continue;
        await client.remove(
          KanbanPaths.remoteBackupDir(_remoteBase(config), id),
        );
      }
    });
  }

  bool _isSafeBackupId(String id) =>
      id.isNotEmpty &&
      !id.contains('/') &&
      !id.contains('\\') &&
      !id.contains('..');
}
