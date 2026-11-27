part of 'webdav_sync_service.dart';

mixin _WebDavSyncPush
    on
        _WebDavSyncHost,
        _WebDavSyncScheduler,
        _WebDavSyncClientIo,
        _WebDavSyncLiveArchive,
        _WebDavSyncAttachments {
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
  }) async {
    if (_syncInFlight || _pushInFlight) {
      _pushPending = true;
      _pushPendingForce = force || _pushPendingForce;
      return;
    }
    if (!force) {
      print(
          'Automatic push ignored: only manual upload or merge write-back updates the cloud');
      return;
    }

    _pushInFlight = true;
    final runId = _syncRunId;
    var enteredSyncing = false;
    try {
      final config = await _loadConfig();
      _applyConfigTiming(config);
      if (!config.enabled || !config.isConfigured) return;

      final client = _client(config);
      if (client == null) return;

      if (_cancelRequested) {
        print('Skipping push: sync was canceled');
        _clearCancelFlag();
        return;
      }

      enteredSyncing = true;
      _setStatus(SyncStatus.syncing);
      _lastAttachmentError = null;
      _resetEnsuredRemoteDirs();
      _setProgress(const SyncProgress(phase: SyncPhase.discovering));

      await _runPushCore(
        config: config,
        client: client,
        runId: runId,
        force: force,
      );
    } on SyncCancelledException {
      print('Push sync aborted');
      if (enteredSyncing && status == SyncStatus.syncing) {
        _setStatus(SyncStatus.idle);
      }
      unawaited(refreshPendingUploadCount());
    } catch (e) {
      if (!_shouldCommit(runId)) {
        print('Push sync canceled; ignoring error: $e');
        unawaited(refreshPendingUploadCount());
      } else {
        _noteFailure(e);
        if (enteredSyncing) {
          _setStatus(SyncStatus.error, error: e.toString());
        }
        unawaited(refreshPendingUploadCount());
      }
    } finally {
      _pushInFlight = false;
      if (!_pushPending &&
          !_pullPending &&
          !_wallpaperPushPending &&
          !_wallpaperPullPending) {
        _clearProgress();
      }
      if (_cancelRequested) {
        _clearCancelFlag();
      }
      _drainPendingWork(forceFallback: force);
    }
  }

  @override
  Future<void> _runPushCore({
    required WebDavConfig config,
    required Client client,
    required int runId,
    bool force = false,
    BackupPackage? package,
  }) async {
    _ensureNotCancelled(runId);
    final remoteScope = _remoteScopeFor(config);
    await _syncBaseStore.ensureRemoteScope(remoteScope);
    _ensureNotCancelled(runId);

    late final BackupPackage captured;
    if (package != null) {
      captured = package;
    } else {
      captured = await _withLocalTransaction(_captureBackupPackage);
    }
    final workspaceSnapshot = captured.workspace;
    final base = _remoteBase(config);
    final bytes = const BackupArchiveService().encode(captured);
    final digest = LiveArchiveMarker.hashBytes(bytes);

    _ensureNotCancelled(runId);
    _setProgress(
      const SyncProgress(
        phase: SyncPhase.uploading,
        completed: 0,
        total: 1,
        currentLabel: 'Workspace archive',
      ),
    );
    await _writeLiveArchive(
      client: client,
      archivePath: KanbanPaths.remoteLiveWorkspaceArchivePath(base),
      markerPath: KanbanPaths.remoteLiveWorkspaceMarkerPath(base),
      archiveId: KanbanPaths.liveWorkspaceArchiveId,
      bytes: bytes,
    );
    _setProgress(
      const SyncProgress(
        phase: SyncPhase.uploading,
        completed: 1,
        total: 1,
        currentLabel: 'Workspace archive',
      ),
    );

    _ensureNotCancelled(runId);
    _setProgress(const SyncProgress(phase: SyncPhase.finalizing));
    if (!_syncBaseStore.isLegacyTreeCleaned(remoteScope)) {
      await _cleanupLegacyWorkspaceTree(client, base);
      if (_shouldCommit(runId)) {
        await _syncBaseStore.markLegacyTreeCleaned(remoteScope);
      }
    }

    if (!_shouldCommit(runId)) {
      throw const SyncCancelledException();
    }

    await _withLocalTransaction(() async {
      final latest = await _loadWorkspace();
      final latestLabelTrash = _loadLabelTrash();
      await _syncBaseStore.save(
        workspaceSnapshot,
        remoteScope: remoteScope,
        labelTrash: captured.labelTrash,
      );
      await _syncBaseStore.saveLiveWorkspaceSha256(digest);
      if (shouldQueueFollowUpPushAfterUpload(
            uploaded: workspaceSnapshot,
            latest: latest,
          ) ||
          !labelTrashListsEqual(captured.labelTrash, latestLabelTrash)) {
        print(
            'New local changes appeared after push; advanced SyncBase and queued an incremental push');
        _pushPending = true;
        _pushPendingForce = _pushPendingForce || force;
      } else {
        _markPendingUploadsCleared();
      }
    });

    await _noteMissingWallpapersIfNeeded(workspaceSnapshot);
    _noteSuccess();
    _setStatus(SyncStatus.success);
    unawaited(refreshPendingUploadCount());
  }
}
