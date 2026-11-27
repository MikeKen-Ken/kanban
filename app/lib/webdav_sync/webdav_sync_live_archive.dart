part of 'webdav_sync_service.dart';

mixin _WebDavSyncLiveArchive on _WebDavSyncHost, _WebDavSyncClientIo {
  Future<void> _writeLiveArchive({
    required Client client,
    required String archivePath,
    required String markerPath,
    required String archiveId,
    required Uint8List bytes,
  }) async {
    _ensureNotCancelled();
    await _ensureParentDir(client, archivePath);
    final stagingPath =
        '$archivePath.part.${DateTime.now().microsecondsSinceEpoch}';
    var staged = false;
    try {
      await _writeBytes(client, stagingPath, bytes);
      staged = true;
      _ensureNotCancelled();
      try {
        await client.rename(stagingPath, archivePath, true);
        staged = false;
      } catch (_) {
        // 个别 WebDAV 服务不支持带覆盖的 MOVE，移除暂存后直接覆盖目标路径；
        // 全程不提前删除 markerPath，避免并发读端误判云端为空库。
        try {
          await client.remove(stagingPath);
          staged = false;
        } catch (_) {
          // 忽略暂存清理失败。
        }
        _ensureNotCancelled();
        await _writeBytes(client, archivePath, bytes);
      }
    } finally {
      if (staged) {
        try {
          await client.remove(stagingPath);
        } catch (_) {
          // 忽略中断后的暂存清理失败。
        }
      }
    }
    _ensureNotCancelled();
    final marker = LiveArchiveMarker(
      id: archiveId,
      sizeBytes: bytes.length,
      sha256: LiveArchiveMarker.hashBytes(bytes),
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    await _writeJson(client, markerPath, marker.toJson());
  }

  Future<bool> _remoteArchiveExistsWithoutMarker(
    Client client,
    String base,
    String fileName,
  ) async {
    final archivePath = '$base/$fileName';
    try {
      await client.readProps(archivePath);
      return true;
    } on Object catch (e) {
      if (_isRemoteNotFound(e)) return false;
      final entries = await _readDirWithFallback(client, base);
      return entries.any((file) {
        if (file.isDir == true) return false;
        final name = file.name?.trim() ?? file.path?.split('/').last.trim() ?? '';
        return name == fileName;
      });
    }
  }

  Future<bool> _anyAttachmentMissing(
    ProjectWorkspaceSnapshot workspace,
  ) async {
    if (!_attachmentSync.isAvailable) return false;
    for (final entry in workspace.manifest.projects) {
      final board = workspace.boards[entry.id];
      if (board == null) continue;
      final trash = workspace.projectTrash[entry.id] ?? TrashBin.empty;
      final settings = workspace.settings[entry.id];
      final refs = _attachmentSync.referencedIdsByKind(
        board,
        trash,
        settings: settings,
      );
      for (final id in refs.imageIds) {
        if (!await _attachmentSync.exists(entry.id, id)) return true;
      }
      for (final id in refs.fileIds) {
        if (!await _attachmentSync.exists(
          entry.id,
          id,
          isFileAttachment: true,
        )) {
          return true;
        }
      }
    }
    return false;
  }

  Future<LiveArchiveMarker?> _readLiveArchiveMarker(
    Client client,
    String markerPath,
  ) async {
    final json = await _readJson(client, markerPath);
    return LiveArchiveMarker.tryParse(json);
  }

  Future<Uint8List?> _readLiveArchiveBytes({
    required Client client,
    required String archivePath,
    required String markerPath,
    required String expectedId,
  }) async {
    final marker = await _readLiveArchiveMarker(client, markerPath);
    if (marker == null || marker.id != expectedId) return null;
    final bytes = await _readBytes(client, archivePath);
    if (bytes == null) {
      throw const FormatException('云端压缩包不完整，请重新上传');
    }
    if (!marker.matchesBytes(bytes)) {
      throw const FormatException('云端压缩包校验失败，请重新上传');
    }
    return bytes;
  }

  Future<void> _removeRemoteIfExists(Client client, String path) async {
    try {
      await client.remove(path);
    } catch (error) {
      if (_isRemoteNotFound(error)) return;
      // 个别网盘对目录删除返回含 locked 的瞬时错误，忽略后不影响 live 包。
      final message = error.toString().toLowerCase();
      if (message.contains('423') || message.contains('locked')) return;
      rethrow;
    }
  }

  /// 新格式工作区包写成功后删除旧 JSON 树；保留壁纸目录与时间点备份。
  Future<void> _cleanupLegacyWorkspaceTree(Client client, String base) async {
    final files = [
      KanbanPaths.remoteProjectsPath(base),
      KanbanPaths.remoteAppTrashPath(base),
      KanbanPaths.remoteSharedContentPath(base),
      KanbanPaths.remoteSyncIndexPath(base),
      KanbanPaths.remoteBoardPath(base),
    ];
    for (final path in files) {
      _ensureNotCancelled();
      await _removeRemoteIfExists(client, path);
    }
    await _removeRemoteIfExists(client, KanbanPaths.remoteProjectsDir(base));
    await _removeRemoteIfExists(client, KanbanPaths.remoteColumnsDir(base));
  }

  Future<bool> _anyWallpaperFileMissing(
    ProjectWorkspaceSnapshot workspace,
  ) async {
    if (!_attachmentSync.isAvailable) return false;
    for (final asset in workspace.sharedContent.wallpapers) {
      if (!await _attachmentSync.wallpaperExists(asset.id)) return true;
    }
    return false;
  }

  Future<void> _noteMissingWallpapersIfNeeded(
    ProjectWorkspaceSnapshot workspace,
  ) async {
    if (!await _anyWallpaperFileMissing(workspace)) return;
    final current = attachmentSyncWarning;
    if (current == null || current.isEmpty) {
      attachmentSyncWarning = kDownloadWallpaperLibraryHint;
      return;
    }
    if (!current.contains(kDownloadWallpaperLibraryHint)) {
      attachmentSyncWarning = '$current；$kDownloadWallpaperLibraryHint';
    }
  }
}
