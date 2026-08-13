part of 'webdav_sync_service.dart';

mixin _WebDavSyncPush
    on
        _WebDavSyncHost,
        _WebDavSyncScheduler,
        _WebDavSyncClientIo,
        _WebDavSyncAttachments {
  String _remotePathForUploadItem(String base, SyncUploadItem item) {
    switch (item.kind) {
      case SyncUploadKind.projectsManifest:
        return KanbanPaths.remoteProjectsPath(base);
      case SyncUploadKind.appTrash:
        return KanbanPaths.remoteAppTrashPath(base);
      case SyncUploadKind.sharedContent:
        return KanbanPaths.remoteSharedContentPath(base);
      case SyncUploadKind.boardMetadata:
        return KanbanPaths.remoteProjectBoardPath(base, item.projectId!);
      case SyncUploadKind.column:
        return KanbanPaths.remoteProjectColumnPath(
          base,
          item.projectId!,
          item.columnId!,
        );
      case SyncUploadKind.settings:
        return KanbanPaths.remoteProjectSettingsPath(base, item.projectId!);
      case SyncUploadKind.trash:
        return KanbanPaths.remoteProjectTrashPath(base, item.projectId!);
    }
  }

  Future<void> _ensureProjectDir(
    Client client,
    String base,
    String projectId,
  ) {
    return _ensureRemoteDir(
      client,
      KanbanPaths.remoteProjectDir(base, projectId),
    );
  }

  /// 按计划增量上传 JSON；[baseline] 为 null 时全量上传。
  Future<int> _pushWorkspaceJson({
    required Client client,
    required String base,
    required ProjectWorkspaceSnapshot workspace,
    ProjectWorkspaceSnapshot? baseline,
    required int runId,
  }) async {
    final plan = buildSyncUploadPlan(
      workspace: workspace,
      baseline: baseline,
    );
    final total = plan.items.length;
    var completed = 0;
    _setProgress(
      SyncProgress(
        phase: SyncPhase.uploading,
        completed: 0,
        total: total,
        skipped: plan.skippedFileCount,
        currentLabel: plan.isEmpty ? '无需上传 JSON' : null,
      ),
    );

    Future<void> uploadItem(SyncUploadItem item) async {
      _ensureNotCancelled(runId);
      _setProgress(
        SyncProgress(
          phase: SyncPhase.uploading,
          completed: completed,
          total: total,
          skipped: plan.skippedFileCount,
          currentLabel: item.label,
        ),
      );
      final projectId = item.projectId;
      if (projectId != null) {
        await _ensureProjectDir(client, base, projectId);
      }
      await _writeJson(
        client,
        _remotePathForUploadItem(base, item),
        item.json,
      );
      completed++;
      _setProgress(
        SyncProgress(
          phase: SyncPhase.uploading,
          completed: completed,
          total: total,
          skipped: plan.skippedFileCount,
          currentLabel: item.label,
        ),
      );
    }

    // 先并行写列文件，再并行写 board 等，避免元数据引用尚未上传的列
    await runBounded(
      plan.items.where((item) => item.kind == SyncUploadKind.column),
      action: uploadItem,
    );
    await runBounded(
      plan.items.where((item) => item.kind != SyncUploadKind.column),
      action: uploadItem,
    );

    for (final projectId in plan.projectsNeedingColumnCleanup) {
      _ensureNotCancelled(runId);
      final keep = plan.keepColumnIdsByProject[projectId] ?? const <String>{};
      await _cleanupRemoteColumns(
        client,
        KanbanPaths.remoteProjectColumnsDir(base, projectId),
        keep,
      );
    }

    if (plan.needsProjectCleanup) {
      _ensureNotCancelled(runId);
      await _cleanupRemoteProjects(
        client,
        KanbanPaths.remoteProjectsDir(base),
        plan.keepProjectIds,
      );
    }

    // 无论是否有 JSON 变更，都重写索引，便于旧远端补齐与拉取跳过
    _ensureNotCancelled(runId);
    await _writeSyncIndex(client, base, workspace);

    return plan.skippedFileCount;
  }

  Future<void> _writeSyncIndex(
    Client client,
    String base,
    ProjectWorkspaceSnapshot workspace,
  ) async {
    final index = buildSyncIndex(workspace);
    await _writeJson(
      client,
      KanbanPaths.remoteSyncIndexPath(base),
      index.toJson(),
    );
  }

  Future<SyncIndex?> _readSyncIndex(Client client, String base) async {
    final json = await _readJson(client, KanbanPaths.remoteSyncIndexPath(base));
    if (json == null) return null;
    final index = SyncIndex.fromJson(json);
    if (!index.isSupportedSchema) return null;
    return index;
  }

  @override
  Future<void> _pushNow({
    bool force = false,
    ProjectWorkspaceSnapshot? workspace,
    ProjectWorkspaceSnapshot? baseline,
  }) async {
    if (_syncInFlight) {
      _pushPending = true;
      _pushPendingForce = force || _pushPendingForce;
      return;
    }
    if (_pushInFlight) {
      _pushPending = true;
      _pushPendingForce = force || _pushPendingForce;
      return;
    }
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;
    if (!force) {
      print('已忽略自动推送：仅手动上传或合并回写会写入云端');
      return;
    }

    final client = _client(config);
    if (client == null) return;

    // 用户刚取消时勿清标志开跑（例如 pull 交接 push 之间的窗口）
    if (_cancelRequested) {
      print('跳过推送：同步已取消');
      _clearCancelFlag();
      return;
    }

    final runId = _syncRunId;
    _pushInFlight = true;
    _setStatus(SyncStatus.syncing);
    _lastAttachmentError = null;
    _resetEnsuredRemoteDirs();
    _setProgress(const SyncProgress(phase: SyncPhase.discovering));

    try {
      _ensureNotCancelled(runId);
      final captured = workspace ?? await _captureWorkspace();
      final uploadBaseline =
          baseline ?? (workspace == null ? await _syncBaseStore.load() : null);
      final base = _remoteBase(config);

      final skipped = await _pushWorkspaceJson(
        client: client,
        base: base,
        workspace: captured,
        baseline: uploadBaseline,
        runId: runId,
      );
      print('增量推送：跳过 $skipped 个未变更 JSON 文件');

      _ensureNotCancelled(runId);
      final attachmentFailures = await _pushAllProjectAttachments(
        client: client,
        base: base,
        workspace: captured,
        runId: runId,
      );
      final wallpaperFailures = await _pushWallpapers(
        client,
        base,
        captured.sharedContent,
      );

      if (!_shouldCommit(runId)) {
        throw const SyncCancelledException();
      }

      _setProgress(const SyncProgress(phase: SyncPhase.finalizing));
      // 已上传内容就是新的合并基线。本机若其间又有写入，只排队增量补传，
      // 不能卡住旧 SyncBase，否则下一轮会把刚传过的文件再全量上传。
      await _withLocalTransaction(() async {
        final latest = await _loadWorkspace();
        await _syncBaseStore.save(captured);
        if (shouldQueueFollowUpPushAfterUpload(
          uploaded: captured,
          latest: latest,
        )) {
          print('推送后本地已有新变更，已推进 SyncBase，排队增量推送');
          _pushPending = true;
          _pushPendingForce = _pushPendingForce || force;
        }
      });

      _applyAttachmentSyncWarning(attachmentFailures + wallpaperFailures);
      _noteSuccess();
      _setStatus(SyncStatus.success);
      unawaited(refreshPendingUploadCount());
    } on SyncCancelledException {
      print('推送同步已中止');
      if (status == SyncStatus.syncing) {
        _setStatus(SyncStatus.idle);
      }
      unawaited(refreshPendingUploadCount());
    } catch (e) {
      if (!_shouldCommit(runId)) {
        print('推送同步已取消，忽略错误：$e');
        unawaited(refreshPendingUploadCount());
      } else {
        _noteFailure(e);
        _setStatus(SyncStatus.error, error: e.toString());
        unawaited(refreshPendingUploadCount());
      }
    } finally {
      _pushInFlight = false;
      if (!_pushPending && !_pullPending) {
        _clearProgress();
      }
      if (_cancelRequested) {
        _clearCancelFlag();
      }
      _drainPendingWork(forceFallback: force);
    }
  }

  Future<void> _cleanupRemoteColumns(
    Client client,
    String columnsDir,
    Set<String> keepIds,
  ) async {
    try {
      final files = await client.readDir(columnsDir);
      for (final file in files) {
        final id = KanbanPaths.columnIdFromRemoteFile(file.path ?? '');
        if (id == null || keepIds.contains(id)) continue;
        await client.remove(file.path!);
      }
    } catch (_) {
      // note: 远端 columns 目录不存在时忽略
    }
  }

  Future<void> _cleanupRemoteProjects(
    Client client,
    String projectsDir,
    Set<String> keepIds,
  ) async {
    try {
      final dirs = await client.readDir(projectsDir);
      for (final entry in dirs) {
        final name = (entry.path ?? '').split('/').last;
        if (name.isEmpty || keepIds.contains(name)) continue;
        await client.remove(entry.path!);
      }
    } catch (_) {
      // note: 远端 projects 目录不存在时忽略
    }
  }
}
