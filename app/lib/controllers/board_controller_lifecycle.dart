part of 'board_controller.dart';

extension BoardControllerLifecycle on BoardController {
  Future<void> initializeReminders({bool requestPermission = false}) async {
    try {
      await _reminderScheduler.initialize();
      if (requestPermission) {
        await _requestNotificationPermissionAndPersist();
      }
      await _rescheduleReminders();
    } catch (error) {
      debugPrint('初始化任务提醒失败：$error');
    }
  }

  /// 安装后首次进入界面时申请通知权限（需 Activity 就绪）。
  Future<bool> ensureNotificationPermissionOnFirstLaunch() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    if (appSettings.hasRequestedNotificationPermission) {
      return _reminderScheduler.areNotificationsEnabled();
    }
    return _requestNotificationPermissionAndPersist();
  }

  /// 设置页：已授权则重新调度；未授权则弹窗；永久拒绝则打开系统设置。
  Future<NotificationPermissionResult> enableRemindersFromSettings() async {
    try {
      await _reminderScheduler.initialize();
      final alreadyEnabled = await _reminderScheduler.areNotificationsEnabled();
      if (alreadyEnabled) {
        await _rescheduleReminders();
        return NotificationPermissionResult.enabled;
      }

      final granted = await _requestNotificationPermissionAndPersist();
      if (granted) {
        await _rescheduleReminders();
        return NotificationPermissionResult.enabled;
      }

      // 再请求仍未授权，多半是永久拒绝，引导系统设置。
      final opened = await _reminderScheduler.openSystemNotificationSettings();
      return opened
          ? NotificationPermissionResult.openedSystemSettings
          : NotificationPermissionResult.denied;
    } catch (error) {
      debugPrint('启用任务提醒失败：$error');
      return NotificationPermissionResult.denied;
    }
  }

  Future<bool> notificationsEnabled() =>
      _reminderScheduler.areNotificationsEnabled();

  Future<bool> _requestNotificationPermissionAndPersist() async {
    final granted = await _reminderScheduler.requestPermission();
    if (!appSettings.hasRequestedNotificationPermission) {
      await saveAppSettings(
        appSettings.copyWith(hasRequestedNotificationPermission: true),
      );
    }
    return granted;
  }

  Future<void> _rescheduleReminders() async {
    final workspace = await _loadWorkspaceSnapshot();
    await _reminderScheduler.rescheduleAll(workspace.boards);
  }

  /// 调度前若通知未开，再申请一次（用户正在设置提醒时）。
  Future<void> _scheduleCardReminder({
    required String projectId,
    required String columnId,
    required KanbanCard card,
  }) async {
    if (card.reminderAt == null || card.completed) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final enabled = await _reminderScheduler.areNotificationsEnabled();
      if (!enabled) {
        await _requestNotificationPermissionAndPersist();
      }
    }
    await _reminderScheduler.schedule(
      projectId: projectId,
      columnId: columnId,
      card: card,
    );
  }

  Future<bool> undoLastAction() async {
    return _withBoardMutation(() async {
      final undone = await _undoStack.undo();
      if (undone) notifyListeners();
      return undone;
    });
  }

  Future<bool> redoLastAction() async {
    return _withBoardMutation(() async {
      final redone = await _undoStack.redo();
      if (redone) notifyListeners();
      return redone;
    });
  }

  Future<BackupPackage> captureBackupPackage() async {
    final workspace = await _loadWorkspaceSnapshot();
    final labels = labelTrash;
    final attachments = <String, Uint8List>{};
    final store = attachmentStore;
    if (store != null) {
      for (final project in workspace.manifest.projects) {
        for (final attachmentId
            in await store.listLocalAttachmentIds(project.id)) {
          final source = await store.readBytes(
            projectId: project.id,
            attachmentId: attachmentId,
            thumb: false,
          );
          if (source != null) {
            attachments['attachments/${project.id}/$attachmentId'] = source;
          }
          final fileSource = await store.readFileBytes(
            projectId: project.id,
            attachmentId: attachmentId,
          );
          if (fileSource != null) {
            attachments['attachments/${project.id}/files/$attachmentId'] =
                fileSource;
          }
          final thumb = await store.readBytes(
            projectId: project.id,
            attachmentId: attachmentId,
            thumb: true,
          );
          if (thumb != null) {
            attachments['attachments/${project.id}/thumbs/$attachmentId'] =
                thumb;
          }
        }
      }
    }
    return BackupPackage(
      workspace: workspace,
      attachments: attachments,
      labelTrash: labels,
    );
  }

  Future<Uint8List> createBackupArchive() async {
    // 短持锁捕获工作区；附件二进制读取放锁外，避免长时间阻塞冲突解决等 UI 写操作。
    return const BackupArchiveService().encode(await captureBackupPackage());
  }

  Future<void> restoreBackupArchive(
    Uint8List bytes, {
    BackupRestoreMode mode = BackupRestoreMode.replace,
  }) async {
    return _backupCoordinator.runExclusive(() async {
      final service = const BackupArchiveService();
      final package = service.decode(bytes);
      // 安全备份在看板锁外生成，避免读附件时卡住其它突变。
      final safetyBytes = await createBackupArchive();
      final restorePackage = mode == BackupRestoreMode.merge
          ? const BackupRestoreService().merge(
              current: service.decode(safetyBytes),
              backup: package,
            )
          : package;
      if (_backupHistorySupported) {
        final safetySnapshot =
            await _backupCoordinator.storeArchiveNow(safetyBytes);
        await _repository.savePendingRestoreBackupId(safetySnapshot.id);
      }
      try {
        await _withBoardMutation(() async {
          await _applyBackupPackage(restorePackage);
          if (_backupHistorySupported) {
            await _repository.clearPendingRestoreBackupId();
          }
          notifyListeners();
          _markWorkspaceChanged();
        });
      } catch (error, stackTrace) {
        try {
          await _withBoardMutation(() async {
            await _applyBackupPackage(service.decode(safetyBytes));
            if (_backupHistorySupported) {
              await _repository.clearPendingRestoreBackupId();
            }
            notifyListeners();
            _markWorkspaceChanged();
          });
        } catch (rollbackError) {
          throw StateError(
            '恢复失败且自动回滚失败：$error；回滚错误：$rollbackError',
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  Future<void> _applyBackupPackage(BackupPackage package) async {
    final previousProjectIds = {
      for (final project in manifest?.projects ?? const <ProjectEntry>[])
        project.id,
    };
    await _applyWorkspaceSnapshot(package.workspace);
    labelTrash = package.labelTrash;
    await _repository.saveLabelTrash(labelTrash);
    final store = attachmentStore;
    if (store == null) return;
    for (final entry in package.attachments.entries) {
      final segments = entry.key.split('/');
      if (segments.length < 3) continue;
      final isFile = segments.length >= 4 && segments[2] == 'files';
      final isThumb =
          !isFile && segments.length >= 4 && segments[2] == 'thumbs';
      final attachmentId =
          isFile ? segments[3] : (isThumb ? segments[3] : segments[2]);
      if (isFile) {
        await store.writeFileBytes(
          projectId: segments[1],
          attachmentId: attachmentId,
          bytes: entry.value,
        );
      } else {
        await store.writeBytes(
          projectId: segments[1],
          attachmentId: attachmentId,
          bytes: entry.value,
          thumb: isThumb,
        );
      }
    }
    final restoredProjectIds = {
      for (final project in package.workspace.manifest.projects) project.id,
    };
    for (final projectId in {...previousProjectIds, ...restoredProjectIds}) {
      final keepIds = <String>{
        for (final path in package.attachments.keys)
          if (path.startsWith('attachments/$projectId/') &&
              !path.contains('/thumbs/'))
            path.split('/').last,
        for (final path in package.attachments.keys)
          if (path.startsWith('attachments/$projectId/files/'))
            path.split('/').last,
      };
      await store.deleteOrphans(projectId: projectId, keepIds: keepIds);
    }
    await refreshMissingAttachments();
  }

  Future<BackupSnapshotInfo> createTimePointBackup() =>
      _backupCoordinator.createBackupNow();

  Future<List<BackupSnapshotInfo>> listLocalTimePointBackups() =>
      _backupCoordinator.listLocalBackups();

  Future<List<BackupSnapshotInfo>> listRemoteTimePointBackups() =>
      _syncService.listRemoteBackupSnapshots();

  Future<void> restoreTimePointBackup(
    String id, {
    bool remote = false,
    BackupRestoreMode mode = BackupRestoreMode.replace,
  }) async {
    final bytes = remote
        ? await _syncService.readRemoteBackupSnapshot(id)
        : await _backupCoordinator.readLocalBackup(id);
    if (bytes == null) throw StateError('备份不存在或无法读取');
    await restoreBackupArchive(bytes, mode: mode);
  }

  Future<void> deleteLocalTimePointBackup(String id) =>
      _backupCoordinator.deleteLocalBackup(id);

  List<ProjectEntry> get projects {
    final entries = manifest?.projects ?? const <ProjectEntry>[];
    return sortProjectEntries(
      entries,
      sortMode: appSettings.projectSortMode,
      pinnedProjectIds: appSettings.pinnedProjectIds,
      lastUsedAtByProjectId: appSettings.projectLastUsedAt,
    );
  }

  bool isProjectPinned(String projectId) =>
      appSettings.pinnedProjectIds.contains(projectId);

  /// 读取某项目的主题 id；当前项目以内存中的设置为准
  String themeIdForProject(String projectId) {
    if (projectId == activeProjectId) return projectSettings.themeId;
    return projectThemeIds[projectId] ?? '';
  }

  Future<void> _refreshProjectThemeIds() async {
    final entries = manifest?.projects ?? const <ProjectEntry>[];
    if (entries.isEmpty) {
      projectThemeIds = {};
      return;
    }
    final next = <String, String>{};
    for (final entry in entries) {
      if (entry.id == activeProjectId) {
        next[entry.id] = projectSettings.themeId;
        continue;
      }
      final settings = await _repository.loadProjectSettings(entry.id);
      next[entry.id] = settings.themeId;
    }
    projectThemeIds = next;
  }

  void _setProjectThemeIdsFrom(Map<String, ProjectSettings> settings) {
    projectThemeIds = {
      for (final entry in settings.entries) entry.key: entry.value.themeId,
    };
  }

  /// 所有回收站条目（当前项目 + 已删项目 + 标签），按删除时间倒序
  List<TrashItem> get allTrashItems {
    final items = <TrashItem>[
      ...activeProjectTrash.items,
      ...appTrash.items,
      ...labelTrash,
    ];
    for (final entry in projectTrashes.entries) {
      if (entry.key == activeProjectId) continue;
      final projectTitle = manifest?.findById(entry.key)?.title;
      for (final item in entry.value.items) {
        items.add(
          item.copyWith(
            projectTitle: item.projectTitle ?? projectTitle,
          ),
        );
      }
    }
    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  int get trashItemCount => allTrashItems.length;

  AttachmentStore? get attachmentStore => _repository.attachmentStore;

  Future<Uint8List?> readAttachmentBytes(
    String attachmentId, {
    bool thumb = true,
    String? projectId,
  }) async {
    final store = attachmentStore;
    final pid = projectId ?? activeProjectId;
    if (store == null || pid == null) return null;
    return store.readBytes(
      projectId: pid,
      attachmentId: attachmentId,
      thumb: thumb,
    );
  }

  bool isAttachmentMissing(String attachmentId) =>
      missingAttachmentIds.contains(attachmentId);

  int missingAttachmentsForCard(KanbanCard card) =>
      countMissingAttachmentsForCard(card, missingAttachmentIds);

  Future<void> refreshMissingAttachments({String? projectId}) async {
    final pid = projectId ?? activeProjectId;
    final store = attachmentStore;
    if (store == null || pid == null || board == null) {
      missingAttachmentIds = {};
      notifyListeners();
      return;
    }

    final trash = projectTrashes[pid] ?? activeProjectTrash;
    missingAttachmentIds = await findMissingAttachmentIds(
      store: store,
      projectId: pid,
      board: board!,
      trash: trash,
      settings: projectId == null || projectId == activeProjectId
          ? projectSettings
          : null,
    );
    notifyListeners();
  }

  ProjectEntry? get activeProject {
    if (activeProjectId == null || manifest == null) return null;
    return manifest!.findById(activeProjectId!);
  }

  List<SavedView> get savedViews => sharedContent.savedViews;
  List<CardTemplate> get cardTemplates => sharedContent.cardTemplates;
  List<ActivityEvent> get activeProjectActivity =>
      activityForProject(activeProjectId);

  /// 按项目读取活动历史（不切换当前项目）。
  List<ActivityEvent> activityForProject(String? projectId) {
    final events = [
      ...(sharedContent.activityByProject[projectId]?.events ??
          const <ActivityEvent>[]),
    ];
    events.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return events;
  }

  /// 只读加载某项目设置快照（不切换当前项目）。
  Future<ProjectSettings?> loadProjectSettingsSnapshot(String projectId) async {
    return _withBoardMutation(() async {
      if (projectId == activeProjectId) return projectSettings;
      if (manifest?.findById(projectId) == null) return null;
      return _repository.loadProjectSettings(projectId);
    });
  }

  Future<List<CardReference>> loadAllCardReferences() async {
    final workspace = await _loadWorkspaceSnapshot();
    return buildCardReferences(
      manifest: workspace.manifest,
      boards: workspace.boards,
      customLabels: appSettings.customLabels,
    );
  }

  Future<KanbanStatistics> loadStatistics() async {
    final workspace = await _loadWorkspaceSnapshot();
    return const StatisticsService().calculate(workspace.boards);
  }

  Future<void> saveView({
    String? id,
    required String name,
    required FilterSpec filter,
  }) async {
    return _withBoardMutation(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final viewId = id ?? const Uuid().v4();
      final existing = sharedContent.savedViews
          .where((view) => view.id == viewId)
          .firstOrNull;
      final view = SavedView(
        id: viewId,
        name: name.trim(),
        filter: filter,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      await _persistSharedContent(
        sharedContent.copyWith(
          savedViews: [
            for (final item in sharedContent.savedViews)
              if (item.id != viewId) item,
            view,
          ],
        ),
      );
    });
  }

  Future<void> deleteSavedView(String id) async {
    return _withBoardMutation(() async {
      await _persistSharedContent(
        sharedContent.copyWith(
          savedViews:
              sharedContent.savedViews.where((view) => view.id != id).toList(),
        ),
      );
    });
  }

  Future<String> saveCardAsTemplate({
    required KanbanCard card,
    required String name,
  }) async {
    return _withBoardMutation(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final template = CardTemplate.fromCard(
        id: const Uuid().v4(),
        name: name.trim(),
        card: card,
        updatedAt: now,
      );
      await _persistSharedContent(
        sharedContent.copyWith(
          cardTemplates: [...sharedContent.cardTemplates, template],
        ),
      );
      return template.id;
    });
  }

  Future<String?> createCardFromTemplate({
    required String templateId,
    required String columnId,
  }) async {
    return _withBoardMutation(() async {
      final template = sharedContent.cardTemplates
          .where((item) => item.id == templateId)
          .firstOrNull;
      if (template == null || board == null) return null;
      final cardId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;
      final card = template.createCard(
        cardId: cardId,
        createdAt: now,
        checklistIds: [
          for (var i = 0; i < template.checklist.length; i++) const Uuid().v4(),
        ],
      );
      final columns = board!.columns.map((column) {
        if (column.id != columnId) return column;
        return column.copyWith(
          cards: [
            ...column.cards,
            card.copyWith(order: column.cards.length),
          ],
        );
      }).toList();
      await _persistAndSync(_bump(board!.copyWith(columns: columns)));
      String? trashId;
      _pushUndo(
        '新建「${card.title}」',
        () async {
          trashId = await deleteCard(columnId, cardId);
        },
        redo: () async {
          final id = trashId;
          if (id == null) return;
          final error = await restoreTrashItem(id);
          if (error != null) throw StateError(error);
        },
      );
      await _recordActivity(
        entityId: cardId,
        entityTitle: card.title,
        action: ActivityAction.created,
      );
      return cardId;
    });
  }

  Future<void> deleteCardTemplate(String id) async {
    return _withBoardMutation(() async {
      await _persistSharedContent(
        sharedContent.copyWith(
          cardTemplates:
              removeCardTemplateById(sharedContent.cardTemplates, id),
        ),
      );
    });
  }

  Future<String?> quickCapture(QuickCaptureDraft draft) async {
    return _withBoardMutation(() async {
      if (board == null || draft.title.trim().isEmpty) return null;
      final desiredColumn = draft.columnName?.trim();
      final column = board!.columns.cast<KanbanColumn?>().firstWhere(
            (item) =>
                desiredColumn != null &&
                item!.title.toLowerCase() == desiredColumn.toLowerCase(),
            orElse: () => board!.columns.cast<KanbanColumn?>().firstWhere(
                  (item) => item!.id == 'todo',
                  orElse: () =>
                      board!.columns.isEmpty ? null : board!.columns.first,
                ),
          );
      if (column == null) return null;

      final labelKeys = <String>[];
      for (final name in draft.labels) {
        final existing =
            appSettings.customLabels.cast<KanbanLabel?>().firstWhere(
                  (label) => label!.name.toLowerCase() == name.toLowerCase(),
                  orElse: () => null,
                );
        if (existing != null) {
          labelKeys.add(existing.key);
        } else {
          labelKeys.add(
            await addCustomLabel(
              name,
              projectThemeForId(projectSettings.themeId)
                  .defaultLabelColor
                  .toARGB32(),
            ),
          );
        }
      }

      final priority = switch (draft.priority) {
        QuickCapturePriority.low => CardPriority.low,
        QuickCapturePriority.medium => CardPriority.medium,
        QuickCapturePriority.high => CardPriority.high,
        null => CardPriority.none,
      };
      return addCard(
        column.id,
        draft.title.trim(),
        dueDate: draft.dueDate?.millisecondsSinceEpoch,
        priority: priority,
        labels: labelKeys,
      );
    });
  }

  int get unresolvedConflictCount {
    var n = 0;
    if (board != null) {
      for (final col in board!.columns) {
        for (final card in col.cards) {
          if (card.hasConflict) n++;
        }
      }
      if (board!.conflictTitle != null) n++;
    }
    if (projectSettings.hasConflict) n++;
    if (manifest != null) {
      for (final p in manifest!.projects) {
        if (p.hasConflict) n++;
      }
    }
    return n;
  }
}
