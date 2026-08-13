part of 'webdav_sync_service.dart';

mixin _WebDavSyncPull
    on
        _WebDavSyncHost,
        _WebDavSyncScheduler,
        _WebDavSyncClientIo,
        _WebDavSyncAttachments,
        _WebDavSyncPush {
  Future<KanbanBoard?> _pullLegacyBoard(Client client, String base) async {
    final boardPath = KanbanPaths.remoteBoardPath(base);
    final meta = await _readJson(client, boardPath);
    if (meta == null) return null;

    if (KanbanBoard.isLegacyMonolithic(meta)) {
      return KanbanBoard.fromJson(meta);
    }

    final refs =
        (meta['columns'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final columns = <KanbanColumn>[];
    for (final ref in refs) {
      final id = ref['id'] as String;
      final colJson = await _readJson(
        client,
        KanbanPaths.remoteColumnPath(base, id),
      );
      if (colJson != null) {
        columns.add(KanbanColumn.fromJson(colJson));
      }
    }
    return KanbanBoard.fromMetadataJson(meta, columns);
  }

  Future<ProjectWorkspaceSnapshot?> pullRemote({
    ProjectWorkspaceSnapshot? reuseFrom,
  }) async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return null;

    final client = _client(config);
    if (client == null) return null;

    final base = _remoteBase(config);
    final manifestPath = KanbanPaths.remoteProjectsPath(base);

    try {
      final remoteIndex = await _readSyncIndex(client, base);
      if (reuseFrom != null &&
          remoteIndex != null &&
          syncIndexMatchesWorkspace(remoteIndex, reuseFrom)) {
        print('拉取：远端 sync_index 与 SyncBase 一致，跳过全部 JSON 下载');
        _setProgress(
          SyncProgress(
            phase: SyncPhase.downloading,
            completed: 0,
            total: 0,
            skipped: remoteIndex.files.length,
            currentLabel: 'JSON 未变更',
          ),
        );
        return reuseFrom;
      }

      var skipped = 0;
      var downloaded = 0;

      Future<Map<String, dynamic>?> readRel(
        String absolutePath,
        String relativePath,
        Object? baseJson,
      ) async {
        final reuse = canReuseSyncBaseJson(
          remoteIndex: remoteIndex,
          relativePath: relativePath,
          baseJson: baseJson,
        );
        if (reuse) {
          skipped++;
          _setProgress(
            SyncProgress(
              phase: SyncPhase.downloading,
              completed: downloaded,
              skipped: skipped,
              currentLabel: relativePath,
            ),
          );
          if (baseJson is Map<String, dynamic>) {
            return Map<String, dynamic>.from(baseJson);
          }
          final encoded = jsonDecode(syncCanonicalJson(baseJson!));
          return Map<String, dynamic>.from(encoded as Map);
        }
        final json = await _readJson(client, absolutePath);
        downloaded++;
        _setProgress(
          SyncProgress(
            phase: SyncPhase.downloading,
            completed: downloaded,
            skipped: skipped,
            currentLabel: relativePath,
          ),
        );
        return json;
      }

      final manifestJson = await readRel(
        manifestPath,
        SyncIndexPaths.projects,
        reuseFrom?.manifest.toJson(),
      );

      // note: 兼容旧版 v2 单看板远端结构
      if (manifestJson == null) {
        final legacyBoard = await _pullLegacyBoard(client, base);
        if (legacyBoard == null) return null;

        final now = DateTime.now().millisecondsSinceEpoch;
        final entry = ProjectEntry(
          id: legacyBoard.id,
          title: legacyBoard.title,
          updatedAt: now,
          revision: 1,
        );
        return ProjectWorkspaceSnapshot(
          manifest: ProjectsManifest(
            projects: [entry],
            updatedAt: now,
            revision: 1,
          ),
          boards: {legacyBoard.id: legacyBoard},
          settings: {legacyBoard.id: const ProjectSettings()},
        );
      }

      final manifest = ProjectsManifest.fromJson(manifestJson);
      final boards = <String, KanbanBoard>{};
      final settings = <String, ProjectSettings>{};
      final projectTrash = <String, TrashBin>{};

      for (final entry in manifest.projects) {
        final projectId = entry.id;
        final baseBoard = reuseFrom?.boards[projectId];
        final boardMeta = await readRel(
          KanbanPaths.remoteProjectBoardPath(base, projectId),
          SyncIndexPaths.projectBoard(projectId),
          baseBoard?.toMetadataJson(),
        );
        if (boardMeta == null) continue;

        if (KanbanBoard.isLegacyMonolithic(boardMeta)) {
          boards[projectId] = KanbanBoard.fromJson(boardMeta);
        } else {
          final refs = (boardMeta['columns'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          final baseColumnsById = <String, KanbanColumn>{
            for (final column in baseBoard?.columns ?? const <KanbanColumn>[])
              column.id: column,
          };
          final columns = <KanbanColumn>[];
          for (final ref in refs) {
            final colId = ref['id'] as String;
            final colJson = await readRel(
              KanbanPaths.remoteProjectColumnPath(base, projectId, colId),
              SyncIndexPaths.projectColumn(projectId, colId),
              baseColumnsById[colId]?.toJson(),
            );
            if (colJson != null) {
              columns.add(KanbanColumn.fromJson(colJson));
            }
          }
          boards[projectId] = KanbanBoard.fromMetadataJson(boardMeta, columns);
        }

        final settingsJson = await readRel(
          KanbanPaths.remoteProjectSettingsPath(base, projectId),
          SyncIndexPaths.projectSettings(projectId),
          reuseFrom?.settings[projectId]?.toJson(),
        );
        settings[projectId] = settingsJson == null
            ? const ProjectSettings()
            : ProjectSettings.fromJson(settingsJson);

        final trashJson = await readRel(
          KanbanPaths.remoteProjectTrashPath(base, projectId),
          SyncIndexPaths.projectTrash(projectId),
          (reuseFrom?.projectTrash[projectId] ?? TrashBin.empty).toJson(),
        );
        projectTrash[projectId] =
            trashJson == null ? TrashBin.empty : TrashBin.fromJson(trashJson);
      }

      final appTrashJson = await readRel(
        KanbanPaths.remoteAppTrashPath(base),
        SyncIndexPaths.appTrash,
        reuseFrom?.appTrash.toJson(),
      );
      final appTrash = appTrashJson == null
          ? TrashBin.empty
          : TrashBin.fromJson(appTrashJson);

      final baseShared = reuseFrom?.sharedContent;
      final sharedContentJson = await readRel(
        KanbanPaths.remoteSharedContentPath(base),
        SyncIndexPaths.sharedContent,
        (baseShared == null || baseShared.isUninitialized)
            ? null
            : baseShared.toJson(),
      );
      final sharedContent = sharedContentJson == null
          ? SharedContent.empty
          : SharedContent.fromJson(sharedContentJson);

      if (skipped > 0) {
        print('拉取：跳过 $skipped 个未变更 JSON，下载 $downloaded 个');
      }

      return ProjectWorkspaceSnapshot(
        manifest: manifest,
        boards: boards,
        settings: settings,
        projectTrash: projectTrash,
        appTrash: appTrash,
        sharedContent: sharedContent,
      );
    } on SyncCancelledException {
      rethrow;
    } on Object catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('404') || message.contains('not found')) {
        return null;
      }
      _setStatus(SyncStatus.error, error: e.toString());
      rethrow;
    }
  }

  ProjectWorkspaceSnapshot _mergeWorkspaces(
    ProjectWorkspaceSnapshot local,
    ProjectWorkspaceSnapshot remote,
    ProjectWorkspaceSnapshot? base,
  ) {
    return mergeWorkspaces(local: local, remote: remote, base: base);
  }

  @override
  Future<void> _pullAndMerge({bool userInitiated = false}) async {
    if (_syncInFlight || _pushInFlight) {
      // 仅用户手动同步才排队；自动轮询重叠直接丢弃，避免失败后立即连环重试
      if (userInitiated) {
        _pullPending = true;
        _pullPendingUserInitiated = true;
      }
      return;
    }

    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;

    if (!userInitiated && !_canStartAutoSync(config)) {
      return;
    }

    // note: 手动同步不受自动节流/冷却限制，由用户主动触发

    if (_cancelRequested) {
      print('跳过拉取：同步已取消');
      _clearCancelFlag();
      return;
    }

    final runId = _syncRunId;
    _syncInFlight = true;
    _noteAttempt();
    _setStatus(SyncStatus.syncing);
    _lastAttachmentError = null;
    _setProgress(const SyncProgress(phase: SyncPhase.discovering));
    try {
      _ensureNotCancelled(runId);
      // 短事务捕获本地快照；网络拉取在锁外进行。
      var local = await _captureWorkspace();
      final syncBase = await _syncBaseStore.load();
      _setProgress(const SyncProgress(phase: SyncPhase.downloading));
      final remote = await pullRemote(reuseFrom: syncBase);
      _ensureNotCancelled(runId);
      if (remote == null) {
        // note: 远端为空时上传本地；先结束本回合再 push
        _syncInFlight = false;
        await _pushNow(force: true, workspace: local, baseline: null);
        return;
      }

      _setProgress(const SyncProgress(phase: SyncPhase.merging));
      var merged = _mergeWorkspaces(local, remote, syncBase);
      _ensureNotCancelled(runId);

      // 合并落盘前重新捕获，避免网络期间的本地写入被旧快照覆盖。
      merged = await _withLocalTransaction(() async {
        final latest = await _loadWorkspace();
        final next = _workspaceJsonEquals(latest, local)
            ? merged
            : _mergeWorkspaces(latest, remote, syncBase);
        await _saveWorkspace(next);
        return next;
      });

      final client = _client(config);
      var attachmentFailures = 0;
      if (client != null) {
        final base = _remoteBase(config);
        attachmentFailures += await _pullWallpapers(
          client,
          base,
          merged.sharedContent,
        );
        final projects = merged.manifest.projects;
        var index = 0;
        for (final entry in projects) {
          _ensureNotCancelled(runId);
          index++;
          final board = merged.boards[entry.id];
          if (board == null) continue;
          final trash = merged.projectTrash[entry.id] ?? TrashBin.empty;
          final settings = merged.settings[entry.id];
          _setProgress(
            SyncProgress(
              phase: SyncPhase.attachments,
              completed: index - 1,
              total: projects.length,
              currentLabel: entry.title.trim().isEmpty ? entry.id : entry.title,
            ),
          );
          attachmentFailures += await _pullProjectAttachments(
            client,
            base,
            entry.id,
            board,
            trash,
            settings: settings,
          );
        }
      }

      _applyAttachmentSyncWarning(attachmentFailures);

      // note: 按文件级差异判断；整表 JSON 编码顺序不同不应当触发整表回推
      if (countPendingSyncUploads(workspace: merged, baseline: remote) == 0) {
        if (shouldReconcileAttachmentsWhenJsonEquals(
              jsonEquals: true,
              attachmentSyncAvailable: _attachmentSync.isAvailable,
            ) &&
            client != null) {
          final base = _remoteBase(config);
          attachmentFailures += await _pushAllProjectAttachments(
            client: client,
            base: base,
            workspace: merged,
            runId: runId,
            cleanupOrphans: false,
          );
          attachmentFailures += await _pushWallpapers(
            client,
            base,
            merged.sharedContent,
            cleanupOrphans: false,
          );
          _applyAttachmentSyncWarning(attachmentFailures);
        }
        if (!_shouldCommit(runId)) {
          throw const SyncCancelledException();
        }
        await _syncBaseStore.save(merged);
        _noteSuccess();
        _setStatus(SyncStatus.success);
        unawaited(refreshPendingUploadCount());
        return;
      }

      // note: 合并后按相对远端的增量回推，避免把并集只留在本机
      _ensureNotCancelled(runId);
      _syncInFlight = false;
      await _pushNow(
        force: true,
        workspace: merged,
        baseline: remote,
      );
    } on SyncCancelledException {
      print('拉取同步已中止');
      if (status == SyncStatus.syncing) {
        _setStatus(SyncStatus.idle);
      }
      unawaited(refreshPendingUploadCount());
    } catch (e) {
      if (!_shouldCommit(runId)) {
        print('拉取同步已取消，忽略错误：$e');
        unawaited(refreshPendingUploadCount());
      } else {
        _noteFailure(e);
        _setStatus(SyncStatus.error, error: e.toString());
        unawaited(refreshPendingUploadCount());
      }
    } finally {
      _syncInFlight = false;
      if (!_pushPending && !_pullPending && !_pushInFlight) {
        _clearProgress();
      }
      if (_cancelRequested) {
        _clearCancelFlag();
      }
      _drainPendingWork();
    }
  }
}
