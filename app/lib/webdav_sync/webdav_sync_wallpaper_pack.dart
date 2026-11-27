part of 'webdav_sync_service.dart';

mixin _WebDavSyncWallpaperPack
    on
        _WebDavSyncHost,
        _WebDavSyncScheduler,
        _WebDavSyncClientIo,
        _WebDavSyncLiveArchive,
        _WebDavSyncAttachments {
  @override
  Future<void> _pushWallpaperPack() async {
    if (_syncInFlight || _pushInFlight) {
      _wallpaperPushPending = true;
      return;
    }

    final runId = _syncRunId;
    _pushInFlight = true;
    var enteredSyncing = false;
    try {
      final config = await _loadConfig();
      _applyConfigTiming(config);
      if (!config.enabled || !config.isConfigured) return;
      final client = _client(config);
      if (client == null) return;
      if (_cancelRequested) {
        _clearCancelFlag();
        return;
      }

      enteredSyncing = true;
      _setStatus(SyncStatus.syncing);
      _resetEnsuredRemoteDirs();
      _setProgress(const SyncProgress(phase: SyncPhase.discovering));

      _ensureNotCancelled(runId);
      await _syncBaseStore.ensureRemoteScope(_remoteScopeFor(config));
      final package = await _withLocalTransaction(_captureWallpaperPackage);
      final bytes = const WallpaperArchiveService().encode(package);
      final base = _remoteBase(config);
      _setProgress(
        const SyncProgress(
          phase: SyncPhase.uploading,
          completed: 0,
          total: 1,
          currentLabel: 'Wallpaper archive',
        ),
      );
      await _writeLiveArchive(
        client: client,
        archivePath: KanbanPaths.remoteLiveWallpapersArchivePath(base),
        markerPath: KanbanPaths.remoteLiveWallpapersMarkerPath(base),
        archiveId: KanbanPaths.liveWallpapersArchiveId,
        bytes: bytes,
      );
      _ensureNotCancelled(runId);
      if (!_shouldCommit(runId)) {
        throw const SyncCancelledException();
      }
      await _syncBaseStore.saveLiveWallpapersSha256(
        LiveArchiveMarker.hashBytes(bytes),
      );
      attachmentSyncWarning = null;
      _noteSuccess();
      _setStatus(SyncStatus.success);
    } on SyncCancelledException {
      if (enteredSyncing && status == SyncStatus.syncing) {
        _setStatus(SyncStatus.idle);
      }
    } catch (e) {
      if (!_shouldCommit(runId)) {
        print('Wallpaper upload canceled; ignoring error: $e');
      } else {
        _noteFailure(e);
        if (enteredSyncing) {
          _setStatus(SyncStatus.error, error: e.toString());
        }
      }
    } finally {
      _pushInFlight = false;
      if (!_pushPending &&
          !_pullPending &&
          !_wallpaperPushPending &&
          !_wallpaperPullPending) {
        _clearProgress();
      }
      if (_cancelRequested) _clearCancelFlag();
      _drainPendingWork();
    }
  }

  @override
  Future<void> _pullWallpaperPack() async {
    if (_syncInFlight || _pushInFlight) {
      _wallpaperPullPending = true;
      return;
    }

    final runId = _syncRunId;
    _syncInFlight = true;
    var enteredSyncing = false;
    try {
      final config = await _loadConfig();
      _applyConfigTiming(config);
      if (!config.enabled || !config.isConfigured) return;
      final client = _client(config);
      if (client == null) return;
      if (_cancelRequested) {
        _clearCancelFlag();
        return;
      }

      enteredSyncing = true;
      _setStatus(SyncStatus.syncing);
      _resetEnsuredRemoteDirs();
      _setProgress(const SyncProgress(phase: SyncPhase.downloading));

      _ensureNotCancelled(runId);
      await _syncBaseStore.ensureRemoteScope(_remoteScopeFor(config));
      final base = _remoteBase(config);
      final bytes = await _readLiveArchiveBytes(
        client: client,
        archivePath: KanbanPaths.remoteLiveWallpapersArchivePath(base),
        markerPath: KanbanPaths.remoteLiveWallpapersMarkerPath(base),
        expectedId: KanbanPaths.liveWallpapersArchiveId,
      );
      if (bytes != null) {
        final package = const WallpaperArchiveService().decode(bytes);
        await _withLocalTransaction(
          () => _applySyncedWallpaperPackage(package),
        );
        await _syncBaseStore.saveLiveWallpapersSha256(
          LiveArchiveMarker.hashBytes(bytes),
        );
      }
      if (!_shouldCommit(runId)) {
        throw const SyncCancelledException();
      }
      attachmentSyncWarning = null;
      _noteSuccess();
      _setStatus(SyncStatus.success);
    } on SyncCancelledException {
      if (enteredSyncing && status == SyncStatus.syncing) {
        _setStatus(SyncStatus.idle);
      }
    } catch (e) {
      if (!_shouldCommit(runId)) {
        print('Wallpaper download canceled; ignoring error: $e');
      } else {
        _noteFailure(e);
        if (enteredSyncing) {
          _setStatus(SyncStatus.error, error: e.toString());
        }
      }
    } finally {
      _syncInFlight = false;
      if (!_pushPending &&
          !_pullPending &&
          !_wallpaperPushPending &&
          !_wallpaperPullPending) {
        _clearProgress();
      }
      if (_cancelRequested) _clearCancelFlag();
      _drainPendingWork();
    }
  }
}
