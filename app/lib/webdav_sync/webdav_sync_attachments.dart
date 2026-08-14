part of 'webdav_sync_service.dart';

mixin _WebDavSyncAttachments
    on _WebDavSyncHost, _WebDavSyncScheduler, _WebDavSyncClientIo {

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

  Future<bool> _downloadRemoteImageAttachment(
    Client client,
    String attachmentsDir,
    String base,
    String projectId,
    String attachmentId, {
    bool thumb = false,
  }) async {
    if (await _attachmentSync.exists(
      projectId,
      attachmentId,
      thumb: thumb,
    )) {
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
        return await _attachmentSync.exists(
          projectId,
          attachmentId,
          thumb: thumb,
        );
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
        if (await _attachmentSync.exists(
          projectId,
          attachmentId,
          thumb: thumb,
        )) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }

    return await _attachmentSync.exists(
      projectId,
      attachmentId,
      thumb: thumb,
    );
  }

  Future<bool> _downloadRemoteFileAttachment(
    Client client,
    String attachmentsDir,
    String base,
    String projectId,
    String attachmentId,
  ) async {
    if (await _attachmentSync.exists(
      projectId,
      attachmentId,
      isFileAttachment: true,
    )) {
      return true;
    }

    try {
      var bytes = await _readBytes(
        client,
        KanbanPaths.remoteProjectFileAttachmentPath(
          base,
          projectId,
          attachmentId,
        ),
      );
      if (bytes != null && bytes.isNotEmpty) {
        await _attachmentSync.writeFile(
          projectId,
          attachmentId,
          bytes,
          isFileAttachment: true,
        );
        return await _attachmentSync.exists(
          projectId,
          attachmentId,
          isFileAttachment: true,
        );
      }

      final expectedName =
          KanbanPaths.remoteProjectFileAttachmentFileName(attachmentId);
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
          isFileAttachment: true,
        );
        if (await _attachmentSync.exists(
          projectId,
          attachmentId,
          isFileAttachment: true,
        )) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }

    return await _attachmentSync.exists(
      projectId,
      attachmentId,
      isFileAttachment: true,
    );
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
    final refs = _attachmentSync.referencedIdsByKind(
      board,
      trash,
      settings: settings,
    );
    final keepIds = refs.all;
    final attachmentsDir =
        KanbanPaths.remoteProjectAttachmentsDir(base, projectId);
    await _ensureRemoteDir(client, attachmentsDir);
    final remoteNames =
        await _listRemoteAttachmentNames(client, attachmentsDir);
    final jobs = <Future<void> Function()>[];

    for (final id in refs.imageIds) {
      for (final thumb in const [false, true]) {
        jobs.add(() async {
          _ensureNotCancelled();
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
            return;
          }
          final bytes = await _attachmentSync.readFile(
            projectId,
            id,
            thumb: thumb,
          );
          if (bytes == null) {
            if (!thumb) failed++;
            return;
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
        });
      }
    }

    for (final id in refs.fileIds) {
      jobs.add(() async {
        _ensureNotCancelled();
        final localExists = await _attachmentSync.exists(
          projectId,
          id,
          isFileAttachment: true,
        );
        final remoteName = KanbanPaths.remoteProjectFileAttachmentFileName(id);
        final remoteExists = remoteNames.contains(remoteName);
        if (!shouldUploadAttachmentFile(
          localExists: localExists,
          remoteExists: remoteExists,
        )) {
          return;
        }
        final bytes = await _attachmentSync.readFile(
          projectId,
          id,
          isFileAttachment: true,
        );
        if (bytes == null) {
          failed++;
          return;
        }
        try {
          await _writeBytesWithRetry(
            client,
            KanbanPaths.remoteProjectFileAttachmentPath(
              base,
              projectId,
              id,
            ),
            bytes,
          );
          remoteNames.add(remoteName);
        } catch (e) {
          failed++;
          _lastAttachmentError ??= e.toString();
          // ignore: avoid_print
          print('文件附件上传失败 $projectId/$id: $e');
        }
      });
    }
    await runBounded(jobs, action: (job) => job());

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
    final refs = _attachmentSync.referencedIdsByKind(
      board,
      trash,
      settings: settings,
    );
    final keepIds = refs.all;
    final attachmentsDir =
        KanbanPaths.remoteProjectAttachmentsDir(base, projectId);

    final pullJobs = <Future<void> Function()>[];
    for (final id in refs.imageIds) {
      pullJobs.add(() async {
        _ensureNotCancelled();
        for (final thumb in const [false, true]) {
          await _downloadRemoteImageAttachment(
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
      });
    }

    for (final id in refs.fileIds) {
      pullJobs.add(() async {
        _ensureNotCancelled();
        await _downloadRemoteFileAttachment(
          client,
          attachmentsDir,
          base,
          projectId,
          id,
        );
        if (!await _attachmentSync.exists(
          projectId,
          id,
          isFileAttachment: true,
        )) {
          failed++;
        }
      });
    }
    await runBounded(pullJobs, action: (job) => job());

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
      final id = KanbanPaths.attachmentIdFromAnyRemoteFileName(name);
      if (id == null || keepIds.contains(id)) continue;
      try {
        await client.remove(_remoteFilePath(attachmentsDir, file));
      } catch (_) {
        // note: 单个远端孤儿删除失败时继续
      }
    }
  }

  // ignore: unused_element
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
          ? '$failedCount 个附件同步失败，可点击同步图标重试'
          : '$failedCount 个附件同步失败：$detail';
    } else {
      attachmentSyncWarning = null;
      _lastAttachmentError = null;
    }
  }
}
