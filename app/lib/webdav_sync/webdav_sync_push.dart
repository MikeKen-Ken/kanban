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
    Set<String> ensured,
  ) async {
    if (!ensured.add(projectId)) return;
    try {
      await client.mkdirAll(KanbanPaths.remoteProjectDir(base, projectId));
    } catch (_) {
      // note: 目录已存在时忽略
    }
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
    final ensuredDirs = <String>{};
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

    // note: 先写列文件、再写 board 元数据；计划内保持列项先于同项目 board
    final ordered = [...plan.items]..sort((a, b) {
        final aCol = a.kind == SyncUploadKind.column ? 0 : 1;
        final bCol = b.kind == SyncUploadKind.column ? 0 : 1;
        if (aCol != bCol) return aCol - bCol;
        return 0;
      });

    for (final item in ordered) {
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
        await _ensureProjectDir(client, base, projectId, ensuredDirs);
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
    if (!force && !config.autoSync) return;

    // 非强制推送在冷却期内延后，避免限流风暴
    if (!force) {
      final wait = _remainingCooldown();
      if (wait != null) {
        _scheduleAfterCooldown(() {
          unawaited(_pushNow(force: force));
        });
        return;
      }
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
    _noteAttempt();
    _setStatus(SyncStatus.syncing);
    _lastAttachmentError = null;
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
      // 仅当本机工作区仍与已上传快照一致时推进 SyncBase，避免覆盖同步期间的新本地写入。
      await _withLocalTransaction(() async {
        final latest = await _loadWorkspace();
        if (_workspaceJsonEquals(latest, captured)) {
          await _syncBaseStore.save(captured);
        } else {
          print('推送后本地已有新变更，保留 SyncBase 并排队再次推送');
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
      _clearProgress();
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
