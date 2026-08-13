part of 'board_controller.dart';

extension BoardControllerProjects on BoardController {
  Future<void> switchProject(String projectId) async {
    return _withBoardMutation(() async {
      if (manifest?.findById(projectId) == null) return;
      if (projectId == activeProjectId) return;

      activeProjectId = projectId;
      await _repository.saveActiveProjectId(projectId);
      board = await _repository.loadBoard(projectId);
      projectSettings = await _repository.loadProjectSettings(projectId);
      await _ensureReworkColumnPersisted();
      projectThemeIds[projectId] = projectSettings.themeId;
      activeProjectTrash = projectTrashes[projectId] ?? TrashBin.empty;
      await refreshDisplayableWallpapers();
      await _recordProjectUsed(projectId);
      notifyListeners();
    });
  }

  Future<void> createProject(String title) async {
    return _withBoardMutation(() async {
      final projectId = await createProjectData(title);
      await switchProject(projectId);
    });
  }

  /// 创建项目数据但不改变界面当前项目，供 MCP 等后台调用。
  Future<String> createProjectData(String title) async {
    return _withBoardMutation(() async {
      final projectId = await _repository.createProject(title);
      manifest = await _repository.loadManifest();
      projectTrashes[projectId] = TrashBin.empty;
      projectThemeIds[projectId] = '';
      notifyListeners();
      _markWorkspaceChanged();
      return projectId;
    });
  }

  Future<void> renameActiveProject(String title) async {
    final projectId = activeProjectId;
    if (projectId == null) return;
    await renameProject(projectId, title);
  }

  /// 重命名任意项目，并保持项目清单与看板标题一致。
  Future<void> renameProject(String projectId, String title) async {
    return _withBoardMutation(() async {
      final normalized = title.trim();
      final entry = manifest?.findById(projectId);
      if (entry == null || normalized.isEmpty) return;

      final isActive = projectId == activeProjectId;
      final targetBoard =
          isActive ? board : await _repository.loadBoard(projectId);
      if (targetBoard == null) return;
      if (entry.title == normalized && targetBoard.title == normalized) return;

      final nextBoard = _bump(
        targetBoard.copyWith(
          title: normalized,
          clearConflictTitle: true,
        ),
      );
      await _repository.saveBoard(projectId, nextBoard);
      if (isActive) {
        board = nextBoard;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final projects = manifest!.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          title: normalized,
          updatedAt: now,
          revision: project.revision + 1,
          clearConflictTitle: true,
        );
      }).toList();
      manifest = manifest!.bump().copyWith(projects: projects);
      await _repository.saveManifest(manifest!);
      notifyListeners();
      _markWorkspaceChanged();
    });
  }

  Future<void> saveProjectSettings(ProjectSettings settings) async {
    return _withBoardMutation(() async {
      if (board == null) return;
      final bumped = settings.bump();
      final oldName = projectSettings.doneColumnName;
      final newName = bumped.doneColumnName;

      if (oldName != newName) {
        final doneColumn = _findDoneColumn(board!);
        if (doneColumn != null && doneColumn.title != newName) {
          await renameColumn(doneColumn.id, newName);
        }
      }

      await _persistProjectSettings(bumped);
    });
  }

  /// 为当前看板选择背景图（立即落盘并调度同步）
  Future<String?> setBoardBackgroundFromGallery() async {
    return _withBoardMutation(() async {
      if (board == null || activeProjectId == null) return '看板未就绪';
      final store = attachmentStore;
      if (store == null) return '当前平台不支持图片背景';

      final picked = await pickCardImagesFromGallery();
      if (picked.isEmpty) return null;

      final image = picked.first;
      final CardAttachment attachment;
      try {
        attachment = await store.saveImage(
          projectId: activeProjectId!,
          sourceBytes: image.bytes,
          fileName: image.fileName,
          order: 0,
        );
      } catch (_) {
        return '图片处理失败';
      }

      final previousId = projectSettings.backgroundAttachmentId;
      await _persistProjectSettings(
        projectSettings
            .copyWith(
              backgroundAttachmentId: attachment.id,
              clearConflictSide: true,
            )
            .bump(),
      );

      if (previousId.isNotEmpty && previousId != attachment.id) {
        await store.deleteAttachment(
          projectId: activeProjectId!,
          attachmentId: previousId,
        );
      }
      await refreshMissingAttachments();
      return null;
    });
  }

  /// 清除当前看板背景图
  Future<void> clearBoardBackground() async {
    return _withBoardMutation(() async {
      if (board == null || activeProjectId == null) return;
      final previousId = projectSettings.backgroundAttachmentId;
      if (previousId.isEmpty) return;

      await _persistProjectSettings(
        projectSettings
            .copyWith(
              backgroundAttachmentId: '',
              clearConflictSide: true,
            )
            .bump(),
      );

      final store = attachmentStore;
      if (store != null) {
        await store.deleteAttachment(
          projectId: activeProjectId!,
          attachmentId: previousId,
        );
      }
      await refreshMissingAttachments();
    });
  }

  /// 调整背景遮罩强度（立即落盘并调度同步）
  Future<void> setBoardBackgroundOverlayOpacity(double opacity) async {
    return _withBoardMutation(() async {
      if (board == null) return;
      final next = ProjectSettings.clampOverlayOpacity(opacity);
      if ((projectSettings.backgroundOverlayOpacity - next).abs() < 0.001) {
        return;
      }
      await _persistProjectSettings(
        projectSettings
            .copyWith(
              backgroundOverlayOpacity: next,
              clearConflictSide: true,
            )
            .bump(),
      );
    });
  }

  /// 调整看板卡片表面不透明度（立即落盘并调度同步）
  Future<void> setCardSurfaceOpacity(double opacity) async {
    return _withBoardMutation(() async {
      if (board == null) return;
      final next = ProjectSettings.clampCardSurfaceOpacity(opacity);
      if ((projectSettings.cardSurfaceOpacity - next).abs() < 0.001) {
        return;
      }
      await _persistProjectSettings(
        projectSettings
            .copyWith(
              cardSurfaceOpacity: next,
              clearConflictSide: true,
            )
            .bump(),
      );
    });
  }

  Future<void> updateTitle(String title) async {
    return _withBoardMutation(() async {
      if (board == null) return;
      await _persistAndSync(_bump(board!.copyWith(title: title)));
    });
  }

  /// 新增列；标题 trim 后与现有列精确同名则拒绝，返回错误文案。
  Future<String?> addColumn(
    String title, {
    int? insertIndex,
    String? beforeColumnId,
  }) async {
    return _withBoardMutation(() async {
      if (board == null) return '看板未就绪';
      final normalized = title.trim();
      if (normalized.isEmpty) return '列名称不能为空';
      final columns = [...board!.columns]
        ..sort((a, b) => a.order.compareTo(b.order));
      if (columns.any((col) => col.title == normalized)) {
        return '已存在同名列「$normalized」';
      }
      var index = columns.length;
      if (beforeColumnId != null && beforeColumnId.isNotEmpty) {
        final before = columns.indexWhere((col) => col.id == beforeColumnId);
        if (before >= 0) index = before;
      } else if (insertIndex != null) {
        index = insertIndex.clamp(0, columns.length);
      }
      columns.insert(
        index,
        KanbanColumn(
          id: const Uuid().v4(),
          title: normalized,
          order: index,
          cards: [],
        ),
      );
      final normalizedColumns = [
        for (var i = 0; i < columns.length; i++) columns[i].copyWith(order: i),
      ];
      await _persistAndSync(
        _bump(board!.copyWith(columns: normalizedColumns)),
      );
      return null;
    });
  }

  /// 为当前看板补齐「待返工」列（已有板迁移）；无变更则跳过。
  Future<void> ensureReworkColumn() async {
    return _withBoardMutation(() async {
      await _ensureReworkColumnPersisted();
    });
  }

  Future<void> _ensureReworkColumnPersisted() async {
    final current = board;
    if (current == null) return;
    final next = current.ensureReworkColumn(
      doneColumnTitle: projectSettings.doneColumnName,
    );
    if (identical(next, current)) return;
    final sameShape = next.columns.length == current.columns.length &&
        List.generate(next.columns.length, (i) {
          final a = next.columns[i];
          final b = current.columns[i];
          return a.id == b.id && a.title == b.title && a.order == b.order;
        }).every((ok) => ok);
    if (sameShape) return;
    await _persistAndSync(_bump(next));
  }

  /// 重命名列；与其他列标题冲突时拒绝，返回错误文案。
  Future<String?> renameColumn(String columnId, String title) async {
    return _withBoardMutation(() async {
      if (board == null) return '看板未就绪';
      final normalized = title.trim();
      if (normalized.isEmpty) return '列名称不能为空';
      if (board!.columns.any(
        (col) => col.id != columnId && col.title == normalized,
      )) {
        return '已存在同名列「$normalized」';
      }
      final columns = board!.columns.map((col) {
        if (col.id != columnId) return col;
        return col.copyWith(title: normalized);
      }).toList();
      await _persistAndSync(_bump(board!.copyWith(columns: columns)));
      return null;
    });
  }

  Future<void> reorderColumn(int oldIndex, int newIndex) async {
    return _withBoardMutation(() async {
      if (board == null) return;
      final columns = [...board!.columns];
      if (oldIndex < 0 ||
          oldIndex >= columns.length ||
          newIndex < 0 ||
          newIndex > columns.length) {
        return;
      }

      var targetIndex = newIndex;
      if (targetIndex > oldIndex) targetIndex -= 1;
      if (targetIndex == oldIndex) return;

      final moved = columns.removeAt(oldIndex);
      columns.insert(targetIndex, moved);
      final reordered = [
        for (var i = 0; i < columns.length; i++) columns[i].copyWith(order: i),
      ];
      await _persistAndSync(_bump(board!.copyWith(columns: reordered)));
    });
  }

  Future<void> updateColumnColor(String columnId, int? colorValue) async {
    return _withBoardMutation(() async {
      if (board == null) return;
      final columns = board!.columns.map((col) {
        if (col.id != columnId) return col;
        return col.copyWith(colorValue: colorValue);
      }).toList();
      await _persistAndSync(_bump(board!.copyWith(columns: columns)));
    });
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    final mcpChanged = settings.mcpEnabled != appSettings.mcpEnabled ||
        settings.mcpPort != appSettings.mcpPort;
    final autoClearChanged =
        settings.completedAutoClearDays != appSettings.completedAutoClearDays;
    final trashRetentionChanged =
        settings.trashRetentionDays != appSettings.trashRetentionDays;
    appSettings = settings;
    await _repository.saveAppSettings(settings);
    notifyListeners();
    if (mcpChanged) {
      await _syncMcpHost();
    }
    if (autoClearChanged && settings.completedAutoClearDays > 0) {
      unawaited(purgeExpiredCompletedCards(force: true));
    }
    if (trashRetentionChanged && settings.trashRetentionDays > 0) {
      unawaited(purgeExpiredTrashItems(force: true));
    }
  }

  /// 设置自动时间点备份目录；传入 `null` 时恢复应用默认目录。
  Future<void> setAutoBackupDirectory(String? path) async {
    final normalized = path?.trim();
    final directory =
        normalized == null || normalized.isEmpty ? null : normalized;
    await _backupHistoryStore.setDirectoryPath(directory);
    await saveAppSettings(
      appSettings.copyWith(autoBackupDirectory: directory),
    );
  }

  Future<String> addCustomLabel(String name, int colorValue) async {
    return _withBoardMutation(() async {
      final key = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;
      final label = SharedLabel(
        id: key,
        name: name,
        colorValue: colorValue,
        updatedAt: now,
      );
      await _persistSharedContent(
        sharedContent.copyWith(labels: [...sharedContent.labels, label]),
      );
      return key;
    });
  }

  /// 修改自定义标签名称或颜色；标签 key 不变，已有卡片引用无需迁移。
  Future<bool> updateCustomLabel(
    String key, {
    required String name,
    required int colorValue,
  }) async {
    return _withBoardMutation(() async {
      final normalized = name.trim();
      if (normalized.isEmpty) return false;
      final index =
          appSettings.customLabels.indexWhere((label) => label.key == key);
      if (index < 0) return false;

      final labels = [...sharedContent.labels];
      final sharedIndex = labels.indexWhere((label) => label.id == key);
      if (sharedIndex < 0) return false;
      labels[sharedIndex] = SharedLabel(
        id: key,
        name: normalized,
        colorValue: colorValue,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _persistSharedContent(sharedContent.copyWith(labels: labels));
      return true;
    });
  }

  Future<void> removeCustomLabel(String key) async {
    return _withBoardMutation(() async {
      final label = appSettings.customLabels.cast<KanbanLabel?>().firstWhere(
            (item) => item!.key == key,
            orElse: () => null,
          );
      if (label == null) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      labelTrash = [
        TrashItem.forCustomLabel(
          trashId: const Uuid().v4(),
          deletedAt: now,
          label: label,
        ),
        ...labelTrash,
      ];
      await _persistLabelTrash();

      await _persistSharedContent(
        sharedContent.copyWith(
          labels:
              sharedContent.labels.where((label) => label.id != key).toList(),
        ),
      );
    });
  }

  Future<void> setProjectSortMode(ProjectSortMode mode) async {
    if (mode == appSettings.projectSortMode) return;
    await saveAppSettings(appSettings.copyWith(projectSortMode: mode));
  }

  Future<void> toggleProjectPin(String projectId) async {
    if (manifest?.findById(projectId) == null) return;
    final pinned = [...appSettings.pinnedProjectIds];
    if (pinned.contains(projectId)) {
      pinned.remove(projectId);
    } else {
      pinned.insert(0, projectId);
    }
    await saveAppSettings(appSettings.copyWith(pinnedProjectIds: pinned));
  }

  Future<void> _recordProjectUsed(String projectId) async {
    final lastUsed = Map<String, int>.from(appSettings.projectLastUsedAt);
    lastUsed[projectId] = DateTime.now().millisecondsSinceEpoch;
    appSettings = appSettings.copyWith(projectLastUsedAt: lastUsed);
    await _repository.saveAppSettings(appSettings);
  }

  Future<void> deleteColumn(String columnId) async {
    return _withBoardMutation(() async {
      if (board == null || activeProjectId == null) return;
      final column = board!.columns.cast<KanbanColumn?>().firstWhere(
            (col) => col!.id == columnId,
            orElse: () => null,
          );
      if (column == null) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      await _addToActiveProjectTrash(
        TrashItem.forColumn(
          trashId: const Uuid().v4(),
          deletedAt: now,
          projectId: activeProjectId!,
          projectTitle: board!.title,
          column: column,
        ),
      );

      final columns =
          board!.columns.where((col) => col.id != columnId).toList();
      await _persistAndSync(_bump(board!.copyWith(columns: columns)));
    });
  }

  Future<bool> deleteProject(String projectId) async {
    return _withBoardMutation(() async {
      if (manifest == null || manifest!.projects.length <= 1) return false;

      final entry = manifest!.findById(projectId);
      if (entry == null) return false;

      final projectBoard = projectId == activeProjectId
          ? board!
          : await _repository.loadBoard(projectId);
      final settings = projectId == activeProjectId
          ? projectSettings
          : await _repository.loadProjectSettings(projectId);
      final trash = projectTrashes[projectId] ??
          await _repository.loadProjectTrash(projectId);

      final now = DateTime.now().millisecondsSinceEpoch;
      appTrash = appTrash.bump().copyWith(
        items: [
          TrashItem.forProject(
            trashId: const Uuid().v4(),
            deletedAt: now,
            entry: entry,
            board: projectBoard,
            settings: settings,
            projectTrash: trash,
          ),
          ...appTrash.items,
        ],
      );

      final remaining =
          manifest!.projects.where((p) => p.id != projectId).toList();
      manifest = manifest!.bump().copyWith(projects: remaining);
      await _repository.saveManifest(manifest!);
      projectTrashes.remove(projectId);
      projectThemeIds.remove(projectId);

      if (activeProjectId == projectId) {
        final next = remaining.first;
        activeProjectId = next.id;
        await _repository.saveActiveProjectId(next.id);
        board = await _repository.loadBoard(next.id);
        projectSettings = await _repository.loadProjectSettings(next.id);
        projectThemeIds[next.id] = projectSettings.themeId;
        activeProjectTrash = projectTrashes[next.id] ?? TrashBin.empty;
      }

      await _persistAppTrash();
      notifyListeners();
      return true;
    });
  }

  /// 后台删除项目，但绝不删除或切换界面当前项目。
  Future<bool> deleteProjectInBackground(String projectId) {
    return _withBoardMutation(() async {
      if (projectId == _uiActiveProjectId) return false;
      return deleteProject(projectId);
    });
  }
}

