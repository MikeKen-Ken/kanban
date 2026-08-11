part of 'webdav_sync_service.dart';

mixin _WebDavSyncAttachments
    on _WebDavSyncHost, _WebDavSyncScheduler, _WebDavSyncClientIo {
  Future<int> _pushWallpapers(
    Client client,
    String base,
    SharedContent sharedContent, {
    bool cleanupOrphans = true,
  }) async {
    if (!_attachmentSync.isAvailable) return 0;
    final keepIds = sharedContent.wallpapers.map((item) => item.id).toSet();
    final remoteDir = KanbanPaths.remoteWallpapersDir(base);
    try {
      await client.mkdirAll(remoteDir);
    } catch (_) {
      // note: 目录已存在时忽略
    }
    final remoteNames = await _listRemoteAttachmentNames(client, remoteDir);
    var failed = 0;
    for (final id in keepIds) {
      _ensureNotCancelled();
      for (final thumb in const [false, true]) {
        if (!await _attachmentSync.wallpaperExists(id, thumb: thumb)) {
          if (!thumb) failed++;
          continue;
        }
        final name = KanbanPaths.remoteProjectAttachmentFileName(
          id,
          thumb: thumb,
        );
        if (remoteNames.contains(name)) continue;
        final bytes = await _attachmentSync.readWallpaper(id, thumb: thumb);
        if (bytes == null) continue;
        try {
          await _writeBytesWithRetry(
            client,
            KanbanPaths.remoteWallpaperPath(base, id, thumb: thumb),
            bytes,
          );
          remoteNames.add(name);
        } catch (e) {
          if (!thumb) {
            failed++;
            _lastAttachmentError ??= e.toString();
            // ignore: avoid_print
            print('壁纸上传失败 $id: $e');
          }
        }
      }
    }
    if (cleanupOrphans) {
      await _cleanupRemoteAttachments(client, remoteDir, keepIds);
      await _attachmentSync.deleteOrphanWallpapers(keepIds);
    }
    return failed;
  }

  Future<int> _pullWallpapers(
    Client client,
    String base,
    SharedContent sharedContent,
  ) async {
    if (!_attachmentSync.isAvailable) return 0;
    var failed = 0;
    for (final asset in sharedContent.wallpapers) {
      _ensureNotCancelled();
      for (final thumb in const [false, true]) {
        if (await _attachmentSync.wallpaperExists(asset.id, thumb: thumb)) {
          continue;
        }
        try {
          final bytes = await _readBytes(
            client,
            KanbanPaths.remoteWallpaperPath(base, asset.id, thumb: thumb),
          );
          if (bytes != null && bytes.isNotEmpty) {
            await _attachmentSync.writeWallpaper(
              asset.id,
              bytes,
              thumb: thumb,
            );
          }
        } catch (_) {
          // note: 缩略图缺失不阻断原图下载
        }
      }
      if (!await _attachmentSync.wallpaperExists(asset.id)) failed++;
    }
    await _attachmentSync.deleteOrphanWallpapers(
      sharedContent.wallpapers.map((item) => item.id).toSet(),
    );
    return failed;
  }

  Future<Set<String>> _listRemoteAttachmentNames(
    Client client,
    String attachmentsDir,
  ) async {
    final files = await _readDirWithFallback(client, attachmentsDir);
    final names = <String>{};
    for (final file in files) {
      if (file.isDir == true) continue;
      final name = file.name?.trim();
      if (name != null && name.isNotEmpty) {
        names.add(name);
        continue;
      }
      final path = file.path?.trim();
      if (path == null || path.isEmpty) continue;
      names.add(path.split('/').last);
    }
    return names;
  }

  Future<bool> _downloadRemoteAttachment(
    Client client,
    String attachmentsDir,
    String base,
    String projectId,
    String attachmentId, {
    bool thumb = false,
  }) async {
    if (await _attachmentSync.exists(projectId, attachmentId, thumb: thumb)) {
      return true;
    }

    try {
      var bytes = await _readBytes(
        client,
        KanbanPaths.remoteProjectAttachmentPath(
          base,
          projectId,
          attachmentId,
          thumb: thumb,
        ),
      );
      if (bytes != null && bytes.isNotEmpty) {
        await _attachmentSync.writeFile(
          projectId,
          attachmentId,
          bytes,
          thumb: thumb,
        );
        return await _attachmentSync.exists(projectId, attachmentId,
            thumb: thumb);
      }

      final expectedName = KanbanPaths.remoteProjectAttachmentFileName(
        attachmentId,
        thumb: thumb,
      );
      final files = await _readDirWithFallback(client, attachmentsDir);
      for (final file in files) {
        if (file.isDir == true) continue;
        final name = file.name ?? file.path?.split('/').last ?? '';
        if (name != expectedName) continue;
        final remotePath = _remoteFilePath(attachmentsDir, file);
        bytes = await _readBytes(client, remotePath);
        if (bytes == null || bytes.isEmpty) continue;
        await _attachmentSync.writeFile(
          projectId,
          attachmentId,
          bytes,
          thumb: thumb,
        );
        if (await _attachmentSync.exists(projectId, attachmentId,
            thumb: thumb)) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }

    return await _attachmentSync.exists(projectId, attachmentId, thumb: thumb);
  }

  Future<int> _pushProjectAttachments(
    Client client,
    String base,
    String projectId,
    KanbanBoard board,
    TrashBin trash, {
    ProjectSettings? settings,
    bool cleanupOrphans = true,
  }) async {
    if (!_attachmentSync.isAvailable) return 0;

    var failed = 0;
    final keepIds =
        _attachmentSync.referencedIds(board, trash, settings: settings);
    final attachmentsDir =
        KanbanPaths.remoteProjectAttachmentsDir(base, projectId);
    final remoteNames =
        await _listRemoteAttachmentNames(client, attachmentsDir);

    for (final id in keepIds) {
      _ensureNotCancelled();
      for (final thumb in const [false, true]) {
        final localExists = await _attachmentSync.exists(
          projectId,
          id,
          thumb: thumb,
        );
        final remoteName = KanbanPaths.remoteProjectAttachmentFileName(
          id,
          thumb: thumb,
        );
        final remoteExists = remoteNames.contains(remoteName);
        if (!shouldUploadAttachmentFile(
          localExists: localExists,
          remoteExists: remoteExists,
        )) {
          continue;
        }
        final bytes = await _attachmentSync.readFile(
          projectId,
          id,
          thumb: thumb,
        );
        if (bytes == null) {
          if (!thumb) failed++;
          continue;
        }
        try {
          await _writeBytesWithRetry(
            client,
            KanbanPaths.remoteProjectAttachmentPath(
              base,
              projectId,
              id,
              thumb: thumb,
            ),
            bytes,
          );
          remoteNames.add(remoteName);
        } catch (e) {
          if (!thumb) {
            failed++;
            _lastAttachmentError ??= e.toString();
            // ignore: avoid_print
            print('附件上传失败 $projectId/$id: $e');
          }
        }
      }
    }

    if (cleanupOrphans) {
      try {
        await _cleanupRemoteAttachments(client, attachmentsDir, keepIds);
      } catch (_) {
        // note: 远端孤儿清理失败不影响已上传附件
      }
      try {
        await _attachmentSync.deleteOrphans(projectId, keepIds);
      } catch (_) {
        // note: 本地孤儿清理失败不影响同步结果
      }
    }
    return failed;
  }

  Future<int> _pullProjectAttachments(
    Client client,
    String base,
    String projectId,
    KanbanBoard board,
    TrashBin trash, {
    ProjectSettings? settings,
  }) async {
    if (!_attachmentSync.isAvailable) return 0;

    var failed = 0;
    final keepIds =
        _attachmentSync.referencedIds(board, trash, settings: settings);
    final attachmentsDir =
        KanbanPaths.remoteProjectAttachmentsDir(base, projectId);
    for (final id in keepIds) {
      _ensureNotCancelled();
      for (final thumb in const [false, true]) {
        await _downloadRemoteAttachment(
          client,
          attachmentsDir,
          base,
          projectId,
          id,
          thumb: thumb,
        );
      }
      if (!await _attachmentSync.exists(projectId, id)) {
        failed++;
      }
    }

    try {
      await _attachmentSync.deleteOrphans(projectId, keepIds);
    } catch (_) {
      // note: 本地孤儿清理失败不影响同步结果
    }
    return failed;
  }

  Future<void> _cleanupRemoteAttachments(
    Client client,
    String attachmentsDir,
    Set<String> keepIds,
  ) async {
    final files = await _readDirWithFallback(client, attachmentsDir);
    for (final file in files) {
      if (file.isDir == true) continue;
      final name = file.name ?? file.path?.split('/').last ?? '';
      final id = KanbanPaths.attachmentIdFromRemoteFileName(name);
      if (id == null || keepIds.contains(id)) continue;
      try {
        await client.remove(_remoteFilePath(attachmentsDir, file));
      } catch (_) {
        // note: 单个远端孤儿删除失败时继续
      }
    }
  }

  Future<int> _pushAllProjectAttachments({
    required Client client,
    required String base,
    required ProjectWorkspaceSnapshot workspace,
    required int runId,
    bool cleanupOrphans = true,
  }) async {
    var attachmentFailures = 0;
    final projects = workspace.manifest.projects;
    var index = 0;
    for (final entry in projects) {
      _ensureNotCancelled(runId);
      index++;
      final board = workspace.boards[entry.id];
      final settings = workspace.settings[entry.id];
      final trash = workspace.projectTrash[entry.id] ?? TrashBin.empty;
      if (board == null || settings == null) continue;
      _setProgress(
        SyncProgress(
          phase: SyncPhase.attachments,
          completed: index - 1,
          total: projects.length,
          currentLabel: entry.title.trim().isEmpty ? entry.id : entry.title,
        ),
      );
      attachmentFailures += await _pushProjectAttachments(
        client,
        base,
        entry.id,
        board,
        trash,
        settings: settings,
        cleanupOrphans: cleanupOrphans,
      );
    }
    return attachmentFailures;
  }

  void _applyAttachmentSyncWarning(int failedCount) {
    if (failedCount > 0) {
      final detail = _lastAttachmentError;
      attachmentSyncWarning = (detail == null || detail.isEmpty)
          ? '$failedCount 个图片附件同步失败，可点击同步图标重试'
          : '$failedCount 个图片附件同步失败：$detail';
    } else {
      attachmentSyncWarning = null;
      _lastAttachmentError = null;
    }
  }
}
