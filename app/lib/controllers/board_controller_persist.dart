part of 'board_controller.dart';

extension BoardControllerPersist on BoardController {
  Future<ProjectWorkspaceSnapshot> _loadWorkspaceSnapshot() async {
    return _withBoardMutation(() async {
      final manifest = await _repository.loadManifest();
      final boards = <String, KanbanBoard>{};
      final settings = <String, ProjectSettings>{};
      final projectTrash = <String, TrashBin>{};

      for (final entry in manifest.projects) {
        if (await _repository.storage.hasProjectBoard(entry.id)) {
          boards[entry.id] = await _repository.loadBoard(entry.id);
        }
        settings[entry.id] = await _repository.loadProjectSettings(entry.id);
        projectTrash[entry.id] = await _repository.loadProjectTrash(entry.id);
      }

      return ProjectWorkspaceSnapshot(
        manifest: manifest,
        boards: boards,
        settings: settings,
        projectTrash: projectTrash,
        appTrash: await _repository.loadAppTrash(),
        sharedContent: await _repository.loadSharedContent(),
      );
    });
  }

  Future<void> _applyWorkspaceSnapshot(
    ProjectWorkspaceSnapshot workspace,
  ) async {
    return _withBoardMutation(() async {
      final previousProjectIds = {
        for (final project in manifest?.projects ?? const <ProjectEntry>[])
          project.id,
      };
      final nextProjectIds = {
        for (final project in workspace.manifest.projects) project.id,
      };
      for (final entry in workspace.manifest.projects) {
        final board = workspace.boards[entry.id];
        final settings = workspace.settings[entry.id];
        final trash = workspace.projectTrash[entry.id];
        if (board != null) {
          await _repository.saveBoard(entry.id, board);
        }
        if (settings != null) {
          await _repository.saveProjectSettings(entry.id, settings);
        }
        if (trash != null) {
          await _repository.saveProjectTrash(entry.id, trash);
        }
      }
      await _repository.saveAppTrash(workspace.appTrash);
      await _repository.saveSharedContent(workspace.sharedContent);
      for (final projectId in previousProjectIds.difference(nextProjectIds)) {
        await _repository.storage.deleteProjectData(projectId);
      }
      // 清单最后提交，避免它提前指向尚未完整写入的项目数据。
      await _repository.saveManifest(workspace.manifest);

      manifest = workspace.manifest;
      projectTrashes = Map<String, TrashBin>.from(workspace.projectTrash);
      appTrash = workspace.appTrash;
      sharedContent = workspace.sharedContent;
      _setProjectThemeIdsFrom(workspace.settings);
      await _mirrorSharedLabelsToLocalPreferences();
      final currentId = activeProjectId;
      if (currentId != null && workspace.manifest.findById(currentId) != null) {
        board = workspace.boards[currentId];
        projectSettings =
            workspace.settings[currentId] ?? const ProjectSettings();
        activeProjectTrash =
            workspace.projectTrash[currentId] ?? TrashBin.empty;
      } else if (workspace.manifest.projects.isNotEmpty) {
        final first = workspace.manifest.projects.first;
        activeProjectId = first.id;
        await _repository.saveActiveProjectId(first.id);
        board = workspace.boards[first.id];
        projectSettings =
            workspace.settings[first.id] ?? const ProjectSettings();
        activeProjectTrash = workspace.projectTrash[first.id] ?? TrashBin.empty;
      }
      _backupCoordinator.markChanged();
      await refreshMissingAttachments();
      await refreshDisplayableWallpapers();
    });
  }

  Future<void> _loadTrashState() async {
    appTrash = await _repository.loadAppTrash();
    labelTrash = _repository.loadLabelTrash();
    projectTrashes = {};
    if (manifest != null) {
      for (final entry in manifest!.projects) {
        projectTrashes[entry.id] = await _repository.loadProjectTrash(entry.id);
      }
    }
    if (activeProjectId != null) {
      activeProjectTrash = projectTrashes[activeProjectId!] ?? TrashBin.empty;
    } else {
      activeProjectTrash = TrashBin.empty;
    }
  }

  Future<void> _persistActiveProjectTrash() async {
    if (activeProjectId == null) return;
    projectTrashes[activeProjectId!] = activeProjectTrash;
    await _repository.saveProjectTrash(activeProjectId!, activeProjectTrash);
    notifyListeners();
    _markWorkspaceChanged();
  }

  Future<void> _persistAppTrash() async {
    await _repository.saveAppTrash(appTrash);
    notifyListeners();
    _markWorkspaceChanged();
  }

  Future<void> _persistLabelTrash() async {
    await _repository.saveLabelTrash(labelTrash);
    _backupCoordinator.markChanged();
    notifyListeners();
  }

  Future<void> _addToActiveProjectTrash(TrashItem item) async {
    activeProjectTrash = activeProjectTrash.bump().copyWith(
      items: [item, ...activeProjectTrash.items],
    );
    await _persistActiveProjectTrash();
  }

  Future<void> _init() async {
    try {
      webDavConfig = await _repository.loadWebDavConfig();
      appSettings = _repository.loadAppSettings();
      await _backupHistoryStore.setDirectoryPath(
        appSettings.autoBackupDirectory,
      );
      await _repository.ensureInitialized();

      manifest = await _repository.loadManifest();
      await _recoverInterruptedRestoreIfNeeded();
      manifest = await _repository.loadManifest();
      activeProjectId = _repository.loadActiveProjectId();

      if (activeProjectId == null ||
          manifest!.findById(activeProjectId!) == null) {
        activeProjectId = manifest!.projects.first.id;
        await _repository.saveActiveProjectId(activeProjectId!);
      }

      board = await _repository.loadBoard(activeProjectId!);
      projectSettings = await _repository.loadProjectSettings(activeProjectId!);
      sharedContent = await _repository.loadSharedContent();
      await _initializeSharedLabels();
      await _ensureReworkColumnPersisted();
      await _refreshProjectThemeIds();
      await _loadTrashState();
      await refreshDisplayableWallpapers();
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }

    unawaited(runOverdueAutomations());
    unawaited(_rescheduleReminders());
    unawaited(purgeExpiredCompletedCards());
    unawaited(purgeExpiredTrashItems());

    _syncService.statusStream.listen((status) {
      if (status == SyncStatus.success) {
        unawaited(_reloadUiAfterSync());
      } else if (status == SyncStatus.error) {
        unawaited(refreshMissingAttachments());
      }
      notifyListeners();
    });
    _syncService.progressStream.listen((_) {
      notifyListeners();
    });
    _syncService.pendingUploadCountStream.listen((_) {
      notifyListeners();
    });
    unawaited(_syncService.refreshPendingUploadCount());

    // 同步改为手动：启动与后台不再自动拉取
    _syncService.stopPolling();

    unawaited(_syncMcpHost());
  }

  Future<void> _recoverInterruptedRestoreIfNeeded() async {
    final backupId = _repository.loadPendingRestoreBackupId();
    if (backupId == null) return;
    final bytes = await _backupCoordinator.readLocalBackup(backupId);
    if (bytes == null) {
      throw StateError('检测到未完成恢复，但安全备份不存在：$backupId');
    }
    final package = const BackupArchiveService().decode(bytes);
    await _applyBackupPackage(package);
    await _repository.clearPendingRestoreBackupId();
  }

  Future<void> _syncMcpHost() async {
    await mcpHost.syncWithSettings(
      enabled: appSettings.mcpEnabled,
      port: appSettings.mcpPort,
    );
  }

  /// 只读加载某项目看板快照（不切换当前项目）。
  Future<KanbanBoard?> loadBoardSnapshot(String projectId) async {
    return _withBoardMutation(() async {
      if (projectId == activeProjectId) return board;
      if (manifest?.findById(projectId) == null) return null;
      if (!await _repository.storage.hasProjectBoard(projectId)) return null;
      return _repository.loadBoard(projectId);
    });
  }

  Future<void> _reloadUiAfterSync() {
    return _withBoardMutation(() async {
      manifest = await _repository.loadManifest();
      sharedContent = await _repository.loadSharedContent();
      await _initializeSharedLabels();
      if (activeProjectId != null) {
        board = await _repository.loadBoard(activeProjectId!);
        projectSettings =
            await _repository.loadProjectSettings(activeProjectId!);
        await _ensureReworkColumnPersisted();
        await _loadTrashState();
      }
      await _refreshProjectThemeIds();
      await refreshMissingAttachments();
      await refreshDisplayableWallpapers();
      notifyListeners();
    });
  }

  Future<void> _persistAndSync(KanbanBoard next) async {
    return _withBoardMutation(() async {
      // 以看板 id 为落盘主键，避免与 active 短暂不一致时写错项目文件。
      final projectId = next.id.isNotEmpty ? next.id : activeProjectId;
      if (projectId == null) return;
      if (activeProjectId == projectId) {
        board = next;
      }
      await _repository.saveBoard(projectId, next);
      if (activeProjectId == projectId) {
        await _updateManifestEntry(title: next.title);
      }
      notifyListeners();
      _markWorkspaceChanged();
    });
  }

  Future<void> _persistSharedContent(SharedContent next) async {
    return _withBoardMutation(() async {
      sharedContent = next.bump();
      await _repository.saveSharedContent(sharedContent);
      await _mirrorSharedLabelsToLocalPreferences();
      notifyListeners();
      _markWorkspaceChanged();
    });
  }

  Future<void> _recordActivity({
    required String entityId,
    required String entityTitle,
    required ActivityAction action,
    String entityType = 'card',
    Map<String, String> details = const {},
    ActivitySource? source,
  }) async {
    final projectId = activeProjectId;
    if (projectId == null) return;
    final resolvedSource = source ?? _currentActivitySource;
    final logs = Map<String, ActivityLog>.from(sharedContent.activityByProject);
    final current = logs[projectId] ?? const ActivityLog();
    logs[projectId] = current.add(
      ActivityEvent(
        id: const Uuid().v4(),
        projectId: projectId,
        entityType: entityType,
        entityId: entityId,
        entityTitle: entityTitle,
        action: action,
        occurredAt: DateTime.now().millisecondsSinceEpoch,
        source: resolvedSource,
        details: details,
      ),
    );
    await _persistSharedContent(
      sharedContent.copyWith(activityByProject: logs),
    );
  }

  Future<void> _initializeSharedLabels() async {
    if (sharedContent.isUninitialized && appSettings.customLabels.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _persistSharedContent(
        sharedContent.copyWith(
          labels: [
            for (final label in appSettings.customLabels)
              SharedLabel(
                id: label.key,
                name: label.name,
                colorValue: label.colorValue,
                updatedAt: now,
              ),
          ],
        ),
      );
      return;
    }
    await _mirrorSharedLabelsToLocalPreferences();
  }

  Future<void> _mirrorSharedLabelsToLocalPreferences() async {
    if (sharedContent.isUninitialized) return;
    final labels = [
      for (final label in sharedContent.labels)
        KanbanLabel(
          key: label.id,
          name: label.name,
          color: Color(label.colorValue),
        ),
    ];
    appSettings = appSettings.copyWith(customLabels: labels);
    await _repository.saveAppSettings(appSettings);
  }

  Future<void> _persistProjectSettings(ProjectSettings next) async {
    return _withBoardMutation(() async {
      if (activeProjectId == null) return;
      projectSettings = next;
      projectThemeIds[activeProjectId!] = next.themeId;
      await _repository.saveProjectSettings(activeProjectId!, next);
      notifyListeners();
      _markWorkspaceChanged();
    });
  }

  Future<void> _updateManifestEntry({String? title}) async {
    if (manifest == null || activeProjectId == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final projects = manifest!.projects.map((entry) {
      if (entry.id != activeProjectId) return entry;
      return entry.copyWith(
        title: title ?? entry.title,
        updatedAt: now,
        revision: entry.revision + 1,
      );
    }).toList();
    manifest = manifest!.bump().copyWith(projects: projects);
    await _repository.saveManifest(manifest!);
  }

  KanbanBoard _bump(KanbanBoard current) {
    return current.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      revision: current.revision + 1,
    );
  }

  List<KanbanColumn> _normalizeOrders(List<KanbanColumn> columns) {
    return columns.map((col) {
      final prefs = columnPreferencesFor(col.id);
      if (prefs.sortMode != CardSortMode.custom) {
        return col;
      }

      final unpinned = col.cards
          .where((card) => !prefs.pinnedCardIds.contains(card.id))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      final orderMap = {
        for (var i = 0; i < unpinned.length; i++) unpinned[i].id: i,
      };
      final cards = col.cards
          .map(
            (card) => orderMap.containsKey(card.id)
                ? card.copyWith(order: orderMap[card.id]!)
                : card,
          )
          .toList();
      return col.copyWith(cards: cards);
    }).toList();
  }

  ColumnCardPreferences columnPreferencesFor(String columnId) =>
      resolveColumnCardPreferences(
        stored: projectSettings.columnPreferences[columnId],
        isDoneColumn: isDoneColumn(columnId),
      );

  List<KanbanCard> displayCardsForColumn(KanbanColumn column) {
    final prefs = columnPreferencesFor(column.id);
    return sortColumnCards(
      column.cards,
      sortMode: prefs.sortMode,
      pinnedCardIds: prefs.pinnedCardIds,
    );
  }

  bool isCardPinned(String columnId, String cardId) =>
      columnPreferencesFor(columnId).pinnedCardIds.contains(cardId);

  Future<void> _saveColumnPreferences(
    String columnId,
    ColumnCardPreferences prefs,
  ) async {
    final next = Map<String, ColumnCardPreferences>.from(
      projectSettings.columnPreferences,
    );
    next[columnId] = prefs;
    await _persistProjectSettings(
      projectSettings.bump().copyWith(columnPreferences: next),
    );
  }

  Future<void> setColumnSortMode(String columnId, CardSortMode mode) async {
    return _withBoardMutation(() async {
      final current = columnPreferencesFor(columnId);
      if (current.sortMode == mode) return;
      await _saveColumnPreferences(
        columnId,
        current.copyWith(sortMode: mode),
      );
    });
  }

  Future<void> toggleCardPin(String columnId, String cardId) async {
    return _withBoardMutation(() async {
      if (board == null) return;
      final column = board!.columns.cast<KanbanColumn?>().firstWhere(
            (col) => col!.id == columnId,
            orElse: () => null,
          );
      if (column == null || !column.cards.any((card) => card.id == cardId)) {
        return;
      }

      final prefs = columnPreferencesFor(columnId);
      final pinned = [...prefs.pinnedCardIds];
      if (pinned.contains(cardId)) {
        pinned.remove(cardId);
      } else {
        pinned.insert(0, cardId);
      }
      await _saveColumnPreferences(
          columnId, prefs.copyWith(pinnedCardIds: pinned));
    });
  }

  ({List<String> pinned, Map<String, int> orders}) _pinnedAndOrdersFromDisplay(
    List<KanbanCard> display,
    List<String> pinnedCardIds,
  ) {
    final pinned = <String>[];
    final orders = <String, int>{};
    var order = 0;
    for (final card in display) {
      if (pinnedCardIds.contains(card.id)) {
        pinned.add(card.id);
      } else {
        orders[card.id] = order++;
      }
    }
    return (pinned: pinned, orders: orders);
  }

  List<KanbanCard> _applyPinnedAndOrders(
    List<KanbanCard> cards,
    Map<String, int> orders,
    int updatedAt,
    String? touchedCardId,
  ) {
    return cards
        .map(
          (card) => card.copyWith(
            order: orders[card.id] ?? card.order,
            updatedAt: card.id == touchedCardId ? updatedAt : card.updatedAt,
          ),
        )
        .toList();
  }

  KanbanColumn? _findDoneColumn(KanbanBoard current) {
    return findDoneColumn(
      current,
      doneColumnName: projectSettings.doneColumnName,
    );
  }

  /// 是否为当前项目设置中的已完成列（各项目可配置不同列名）。
  bool isDoneColumn(String columnId) {
    final current = board;
    if (current == null) return false;
    return _findDoneColumn(current)?.id == columnId;
  }
}

