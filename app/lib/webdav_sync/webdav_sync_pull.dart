part of 'webdav_sync_service.dart';

mixin _WebDavSyncPull
    on
        _WebDavSyncHost,
        _WebDavSyncScheduler,
        _WebDavSyncClientIo,
        _WebDavSyncLiveArchive,
        _WebDavSyncAttachments,
        _WebDavSyncPush {
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
        print(
            'Pull: remote sync_index matches SyncBase; skipping all JSON downloads');
        _setProgress(
          SyncProgress(
            phase: SyncPhase.downloading,
            completed: 0,
            total: 0,
            skipped: remoteIndex.files.length,
            currentLabel: 'JSON unchanged',
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

      if (manifestJson == null) return null;

      final manifest = ProjectsManifest.fromJson(manifestJson);
      final boards = <String, KanbanBoard>{};
      final settings = <String, ProjectSettings>{};
      final projectTrash = <String, TrashBin>{};
      final boardMetas = <String, Map<String, dynamic>>{};

      final boardJobs = <Future<void> Function()>[];
      for (final entry in manifest.projects) {
        final projectId = entry.id;
        final baseBoard = reuseFrom?.boards[projectId];
        boardJobs.add(() async {
          final boardMeta = await readRel(
            KanbanPaths.remoteProjectBoardPath(base, projectId),
            SyncIndexPaths.projectBoard(projectId),
            baseBoard?.toMetadataJson(),
          );
          if (boardMeta == null) return;
          boardMetas[projectId] = boardMeta;
        });
      }

      var appTrash = TrashBin.empty;
      var sharedContent = SharedContent.empty;
      boardJobs.add(() async {
        final appTrashJson = await readRel(
          KanbanPaths.remoteAppTrashPath(base),
          SyncIndexPaths.appTrash,
          reuseFrom?.appTrash.toJson(),
        );
        appTrash = appTrashJson == null
            ? TrashBin.empty
            : TrashBin.fromJson(appTrashJson);
      });
      boardJobs.add(() async {
        final baseShared = reuseFrom?.sharedContent;
        final sharedContentJson = await readRel(
          KanbanPaths.remoteSharedContentPath(base),
          SyncIndexPaths.sharedContent,
          (baseShared == null || baseShared.isUninitialized)
              ? null
              : baseShared.toJson(),
        );
        sharedContent = sharedContentJson == null
            ? SharedContent.empty
            : SharedContent.fromJson(sharedContentJson);
      });
      await runBounded(boardJobs, action: (job) => job());

      final followUpJobs = <Future<void> Function()>[];
      final columnsByProject = <String, Map<String, KanbanColumn>>{};

      for (final entry in manifest.projects) {
        final projectId = entry.id;
        final boardMeta = boardMetas[projectId];
        if (boardMeta == null) continue;

        followUpJobs.add(() async {
          final settingsJson = await readRel(
            KanbanPaths.remoteProjectSettingsPath(base, projectId),
            SyncIndexPaths.projectSettings(projectId),
            reuseFrom?.settings[projectId]?.toJson(),
          );
          settings[projectId] = settingsJson == null
              ? const ProjectSettings()
              : ProjectSettings.fromJson(settingsJson);
        });
        followUpJobs.add(() async {
          final trashJson = await readRel(
            KanbanPaths.remoteProjectTrashPath(base, projectId),
            SyncIndexPaths.projectTrash(projectId),
            (reuseFrom?.projectTrash[projectId] ?? TrashBin.empty).toJson(),
          );
          projectTrash[projectId] =
              trashJson == null ? TrashBin.empty : TrashBin.fromJson(trashJson);
        });

        if (boardMeta == null) continue;
        final refs = (boardMeta['columns'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final baseBoard = reuseFrom?.boards[projectId];
        final baseColumnsById = <String, KanbanColumn>{
          for (final column in baseBoard?.columns ?? const <KanbanColumn>[])
            column.id: column,
        };
        for (final ref in refs) {
          final colId = ref['id'] as String;
          followUpJobs.add(() async {
            final colJson = await readRel(
              KanbanPaths.remoteProjectColumnPath(base, projectId, colId),
              SyncIndexPaths.projectColumn(projectId, colId),
              baseColumnsById[colId]?.toJson(),
            );
            if (colJson == null) return;
            (columnsByProject[projectId] ??= {})[colId] =
                KanbanColumn.fromJson(colJson);
          });
        }
      }
      await runBounded(followUpJobs, action: (job) => job());

      for (final entry in manifest.projects) {
        final projectId = entry.id;
        final boardMeta = boardMetas[projectId];
        if (boardMeta == null) continue;
        final refs = (boardMeta['columns'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final loaded = columnsByProject[projectId] ?? const {};
        boards[projectId] = KanbanBoard.fromMetadataJson(
          boardMeta,
          [
            for (final ref in refs)
              if (loaded[ref['id'] as String] != null)
                loaded[ref['id'] as String]!,
          ],
        );
      }

      if (skipped > 0) {
        print(
            'Pull: skipped $skipped unchanged JSON files and downloaded $downloaded');
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

  BackupPackage _mergeBackupPackages({
    required BackupPackage local,
    required BackupPackage remote,
    ProjectWorkspaceSnapshot? base,
  }) {
    final mergedLabelTrash = TrashBin(
      items: local.labelTrash,
      updatedAt: 0,
      revision: 0,
    ).mergeWith(
      TrashBin(items: remote.labelTrash, updatedAt: 0, revision: 0),
    );
    return BackupPackage(
      workspace: _mergeWorkspaces(local.workspace, remote.workspace, base),
      attachments: {...remote.attachments, ...local.attachments},
      labelTrash: mergedLabelTrash.items,
    );
  }

  Future<int> _pullLegacyAttachments({
    required Client client,
    required String base,
    required ProjectWorkspaceSnapshot workspace,
    required int runId,
  }) async {
    var failed = 0;
    final projects = workspace.manifest.projects;
    var index = 0;
    for (final entry in projects) {
      _ensureNotCancelled(runId);
      index++;
      final board = workspace.boards[entry.id];
      if (board == null) continue;
      final trash = workspace.projectTrash[entry.id] ?? TrashBin.empty;
      final settings = workspace.settings[entry.id];
      _setProgress(
        SyncProgress(
          phase: SyncPhase.attachments,
          completed: index - 1,
          total: projects.length,
          currentLabel: entry.title.trim().isEmpty ? entry.id : entry.title,
        ),
      );
      failed += await _pullProjectAttachments(
        client,
        base,
        entry.id,
        board,
        trash,
        settings: settings,
      );
    }
    return failed;
  }

  @override
  Future<void> _pullAndMerge({
    bool userInitiated = false,
    bool replaceLocal = false,
  }) async {
    if (!userInitiated) {
      print(
          'Automatic pull ignored: only manual download or merge reads the cloud');
      return;
    }

    if (_syncInFlight || _pushInFlight) {
      _pullPending = true;
      _pullPendingUserInitiated = true;
      _pullPendingReplace = replaceLocal;
      return;
    }

    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;

    if (_cancelRequested) {
      print('Skipping pull: sync was canceled');
      _clearCancelFlag();
      return;
    }

    final runId = _syncRunId;
    _syncInFlight = true;
    _setStatus(SyncStatus.syncing);
    _lastAttachmentError = null;
    _resetEnsuredRemoteDirs();
    _setProgress(const SyncProgress(phase: SyncPhase.discovering));
    try {
      _ensureNotCancelled(runId);
      var localPkg = await _withLocalTransaction(_captureBackupPackage);
      var local = localPkg.workspace;
      final syncBase = await _syncBaseStore.load();
      _setProgress(const SyncProgress(phase: SyncPhase.downloading));

      final client = _client(config);
      final base = client == null ? '' : _remoteBase(config);
      BackupPackage? remotePkg;
      var fromArchive = false;

      if (client != null) {
        final marker = await _readLiveArchiveMarker(
          client,
          KanbanPaths.remoteLiveWorkspaceMarkerPath(base),
        );
        if (marker != null && marker.id == KanbanPaths.liveWorkspaceArchiveId) {
          final knownSha = _syncBaseStore.loadLiveWorkspaceSha256();
          if (!replaceLocal &&
              knownSha != null &&
              knownSha == marker.sha256 &&
              syncBase != null &&
              _workspaceJsonEquals(local, syncBase)) {
            await _noteMissingWallpapersIfNeeded(local);
            _noteSuccess();
            _setStatus(SyncStatus.success);
            unawaited(refreshPendingUploadCount());
            return;
          }
          final bytes = await _readLiveArchiveBytes(
            client: client,
            archivePath: KanbanPaths.remoteLiveWorkspaceArchivePath(base),
            markerPath: KanbanPaths.remoteLiveWorkspaceMarkerPath(base),
            expectedId: KanbanPaths.liveWorkspaceArchiveId,
          );
          if (bytes == null) {
            throw const FormatException('Cloud workspace archive is incomplete; please upload it again');
          }
          remotePkg = const BackupArchiveService().decode(bytes);
          fromArchive = true;
          await _syncBaseStore.saveLiveWorkspaceSha256(
            LiveArchiveMarker.hashBytes(bytes),
          );
        }
      }

      if (remotePkg == null) {
        final remoteWorkspace = await pullRemote(
          reuseFrom: replaceLocal ? null : syncBase,
        );
        if (remoteWorkspace != null) {
          remotePkg = BackupPackage(workspace: remoteWorkspace);
        }
      }

      _ensureNotCancelled(runId);
      if (remotePkg == null) {
        if (replaceLocal) {
          _setStatus(SyncStatus.error, error: 'No downloadable data found in the cloud');
          return;
        }
        _syncInFlight = false;
        await _pushNow(force: true, package: localPkg);
        return;
      }

      _setProgress(const SyncProgress(phase: SyncPhase.merging));
      late BackupPackage mergedPkg;
      final remote = remotePkg;
      if (replaceLocal) {
        mergedPkg = await _withLocalTransaction(() async {
          await _applySyncedBackupPackage(remote);
          return remote;
        });
      } else {
        mergedPkg = _mergeBackupPackages(
          local: localPkg,
          remote: remote,
          base: syncBase,
        );
        mergedPkg = await _withLocalTransaction(() async {
          final latestPkg = await _captureBackupPackage();
          final next = _workspaceJsonEquals(
            latestPkg.workspace,
            localPkg.workspace,
          )
              ? mergedPkg
              : _mergeBackupPackages(
                  local: latestPkg,
                  remote: remote,
                  base: syncBase,
                );
          await _applySyncedBackupPackage(next);
          return next;
        });
      }

      var attachmentFailures = 0;
      if (!fromArchive && client != null) {
        attachmentFailures += await _pullLegacyAttachments(
          client: client,
          base: base,
          workspace: mergedPkg.workspace,
          runId: runId,
        );
      }
      _applyAttachmentSyncWarning(attachmentFailures);
      await _noteMissingWallpapersIfNeeded(mergedPkg.workspace);

      if (replaceLocal) {
        if (!_shouldCommit(runId)) {
          throw const SyncCancelledException();
        }
        await _syncBaseStore.save(mergedPkg.workspace);
        _noteSuccess();
        _setStatus(SyncStatus.success);
        unawaited(refreshPendingUploadCount());
        return;
      }

      if (countPendingSyncUploads(
            workspace: mergedPkg.workspace,
            baseline: remotePkg.workspace,
          ) ==
          0) {
        if (!_shouldCommit(runId)) {
          throw const SyncCancelledException();
        }
        await _syncBaseStore.save(mergedPkg.workspace);
        _noteSuccess();
        _setStatus(SyncStatus.success);
        unawaited(refreshPendingUploadCount());
        return;
      }

      _ensureNotCancelled(runId);
      _syncInFlight = false;
      await _pushNow(force: true, package: mergedPkg);
    } on SyncCancelledException {
      print('Pull sync aborted');
      if (status == SyncStatus.syncing) {
        _setStatus(SyncStatus.idle);
      }
      unawaited(refreshPendingUploadCount());
    } catch (e) {
      if (!_shouldCommit(runId)) {
        print('Pull sync canceled; ignoring error: $e');
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
