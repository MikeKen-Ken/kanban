part of 'webdav_sync_service.dart';

mixin _WebDavSyncWallpaperPack
    on
        _WebDavSyncHost,
        _WebDavSyncScheduler,
        _WebDavSyncClientIo,
        _WebDavSyncLiveArchive,
        _WebDavSyncAttachments {
  Future<void> _pushWallpaperPack() async {
    if (_syncInFlight || _pushInFlight) {
      print('跳过壁纸上传：已有同步进行中');
      return;
    }
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;
    final client = _client(config);
    if (client == null) return;
    if (_cancelRequested) {
      _clearCancelFlag();
      return;
    }

    final runId = _syncRunId;
    _pushInFlight = true;
    _setStatus(SyncStatus.syncing);
    _resetEnsuredRemoteDirs();
    _setProgress(const SyncProgress(phase: SyncPhase.discovering));
    try {
      _ensureNotCancelled(runId);
      final package = await _withLocalTransaction(_captureWallpaperPackage);
      final bytes = const WallpaperArchiveService().encode(package);
      final base = _remoteBase(config);
      _setProgress(
        const SyncProgress(
          phase: SyncPhase.uploading,
          completed: 0,
          total: 1,
          currentLabel: '壁纸库压缩包',
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
      await _cleanupLegacyWallpapersDir(client, base);
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
      if (status == SyncStatus.syncing) {
        _setStatus(SyncStatus.idle);
      }
    } catch (e) {
      if (!_shouldCommit(runId)) {
        print('壁纸上传已取消，忽略错误：$e');
      } else {
        _noteFailure(e);
        _setStatus(SyncStatus.error, error: e.toString());
      }
    } finally {
      _pushInFlight = false;
      _clearProgress();
      if (_cancelRequested) _clearCancelFlag();
      _drainPendingWork();
    }
  }

  Future<void> _pullWallpaperPack() async {
    if (_syncInFlight || _pushInFlight) {
      print('跳过壁纸下载：已有同步进行中');
      return;
    }
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;
    final client = _client(config);
    if (client == null) return;
    if (_cancelRequested) {
      _clearCancelFlag();
      return;
    }

    final runId = _syncRunId;
    _syncInFlight = true;
    _setStatus(SyncStatus.syncing);
    _resetEnsuredRemoteDirs();
    _setProgress(const SyncProgress(phase: SyncPhase.downloading));
    try {
      _ensureNotCancelled(runId);
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
      } else {
        final workspace = await _captureWorkspace();
        _setProgress(
          const SyncProgress(
            phase: SyncPhase.attachments,
            currentLabel: '兼容旧壁纸目录',
          ),
        );
        final failed = await _pullWallpapers(
          client,
          base,
          workspace.sharedContent,
        );
        if (failed > 0) {
          throw StateError('从旧壁纸目录下载失败 $failed 项');
        }
      }
      if (!_shouldCommit(runId)) {
        throw const SyncCancelledException();
      }
      attachmentSyncWarning = null;
      _noteSuccess();
      _setStatus(SyncStatus.success);
    } on SyncCancelledException {
      if (status == SyncStatus.syncing) {
        _setStatus(SyncStatus.idle);
      }
    } catch (e) {
      if (!_shouldCommit(runId)) {
        print('壁纸下载已取消，忽略错误：$e');
      } else {
        _noteFailure(e);
        _setStatus(SyncStatus.error, error: e.toString());
      }
    } finally {
      _syncInFlight = false;
      _clearProgress();
      if (_cancelRequested) _clearCancelFlag();
      _drainPendingWork();
    }
  }
}
