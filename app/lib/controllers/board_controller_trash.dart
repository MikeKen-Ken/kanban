part of 'board_controller.dart';

extension BoardControllerTrash on BoardController {
  Future<String?> restoreTrashItem(String trashItemId) async {
    return _withBoardMutation(() async {
      final labelIndex =
          labelTrash.indexWhere((item) => item.id == trashItemId);
      if (labelIndex >= 0) {
        return _restoreLabel(labelTrash[labelIndex]);
      }

      final appIndex =
          appTrash.items.indexWhere((item) => item.id == trashItemId);
      if (appIndex >= 0) {
        return _restoreProject(appTrash.items[appIndex]);
      }

      for (final entry in projectTrashes.entries) {
        final index =
            entry.value.items.indexWhere((item) => item.id == trashItemId);
        if (index >= 0) {
          return _restoreProjectItem(entry.key, entry.value.items[index]);
        }
      }

      return '未找到该回收项';
    });
  }

  Future<void> permanentlyDeleteTrashItem(String trashItemId) async {
    return _withBoardMutation(() async {
      TrashItem? target;
      for (final item in allTrashItems) {
        if (item.id == trashItemId) {
          target = item;
          break;
        }
      }

      if (labelTrash.any((item) => item.id == trashItemId)) {
        labelTrash =
            labelTrash.where((item) => item.id != trashItemId).toList();
        await _persistLabelTrash();
        notifyListeners();
        return;
      }

      if (appTrash.items.any((item) => item.id == trashItemId)) {
        if (target != null) {
          await _deleteTrashItemAttachments(target);
        }
        appTrash = appTrash.bump().copyWith(
              items: appTrash.items
                  .where((item) => item.id != trashItemId)
                  .toList(),
            );
        await _persistAppTrash();
        return;
      }

      for (final entry in projectTrashes.entries.toList()) {
        if (!entry.value.items.any((item) => item.id == trashItemId)) continue;
        if (target != null) {
          await _deleteTrashItemAttachments(target);
        }
        final next = entry.value.bump().copyWith(
              items: entry.value.items
                  .where((item) => item.id != trashItemId)
                  .toList(),
            );
        projectTrashes[entry.key] = next;
        if (entry.key == activeProjectId) {
          activeProjectTrash = next;
        }
        await _repository.saveProjectTrash(entry.key, next);
        notifyListeners();
        _markWorkspaceChanged();
        return;
      }
    });
  }

  Future<void> emptyTrash() async {
    return _withBoardMutation(() async {
      for (final item in allTrashItems) {
        await _deleteTrashItemAttachments(item);
      }

      activeProjectTrash = TrashBin.empty.bump();
      appTrash = TrashBin.empty.bump();
      labelTrash = const [];

      for (final entry in manifest?.projects ?? const <ProjectEntry>[]) {
        final empty = TrashBin.empty.bump();
        projectTrashes[entry.id] = empty;
        await _repository.saveProjectTrash(entry.id, empty);
      }

      await _repository.saveAppTrash(appTrash);
      await _persistLabelTrash();
      notifyListeners();
      _markWorkspaceChanged();
    });
  }

  /// 永久删除超过保留天数的回收项。
  ///
  /// [force] 为 true 时忽略节流（例如用户刚改了保留天数）。
  /// 返回实际永久删除的条目数量。
  Future<int> purgeExpiredTrashItems({bool force = false}) async {
    final days = appSettings.trashRetentionDays;
    if (days <= 0) return 0;
    if (isLoading || errorMessage != null) return 0;
    if (_trashAutoClearRunning) return 0;

    final now = DateTime.now();
    if (!force) {
      final last = _lastTrashAutoClearAt;
      if (last != null && now.difference(last) < trashAutoClearMinInterval) {
        return 0;
      }
    }

    _trashAutoClearRunning = true;
    _lastTrashAutoClearAt = now;
    try {
      final expired = selectExpiredTrashItems(
        items: allTrashItems,
        retainDays: days,
        now: now,
      );
      if (expired.isEmpty) return 0;

      var count = 0;
      for (final item in expired) {
        await permanentlyDeleteTrashItem(item.id);
        count++;
      }
      if (count > 0) {
        debugPrint('Automatic trash cleanup: permanently deleted $count items');
      }
      return count;
    } finally {
      _trashAutoClearRunning = false;
    }
  }

  Future<String?> _restoreLabel(TrashItem item) async {
    final label = item.labelPayload;
    if (label == null) return '数据损坏，无法还原';

    if (appSettings.customLabels.any((l) => l.key == label.key)) {
      return '标签已存在';
    }

    await _persistSharedContent(
      sharedContent.copyWith(
        labels: [
          ...sharedContent.labels,
          SharedLabel(
            id: label.key,
            name: label.name,
            colorValue: label.colorValue,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ],
      ),
    );
    labelTrash = labelTrash.where((i) => i.id != item.id).toList();
    await _persistLabelTrash();
    return null;
  }

  Future<String?> _restoreProject(TrashItem item) async {
    final payload = item.projectPayload;
    if (payload == null) return '数据损坏，无法还原';
    if (manifest?.findById(payload.entry.id) != null) {
      return '项目已存在，无法还原';
    }

    await _repository.saveBoard(payload.entry.id, payload.board);
    await _repository.saveProjectSettings(payload.entry.id, payload.settings);
    await _repository.saveProjectTrash(payload.entry.id, payload.projectTrash);

    manifest = manifest!.bump().copyWith(
      projects: [...manifest!.projects, payload.entry],
    );
    await _repository.saveManifest(manifest!);

    projectTrashes[payload.entry.id] = payload.projectTrash;
    projectThemeIds[payload.entry.id] = payload.settings.themeId;
    appTrash = appTrash.bump().copyWith(
          items: appTrash.items.where((i) => i.id != item.id).toList(),
        );
    await _repository.saveAppTrash(appTrash);
    notifyListeners();
    _markWorkspaceChanged();
    return null;
  }

  Future<String?> _restoreProjectItem(String projectId, TrashItem item) async {
    if (manifest?.findById(projectId) == null) {
      return '所属项目不存在，请先还原项目';
    }

    final isActive = projectId == activeProjectId;
    final targetBoard =
        isActive ? board! : await _repository.loadBoard(projectId);

    return switch (item.type) {
      TrashItemType.card =>
        _restoreCardToBoard(projectId, targetBoard, item, isActive),
      TrashItemType.column =>
        _restoreColumnToBoard(projectId, targetBoard, item, isActive),
      _ => '无法还原此类型',
    };
  }

  Future<String?> _restoreCardToBoard(
    String projectId,
    KanbanBoard targetBoard,
    TrashItem item,
    bool isActive,
  ) async {
    final card = item.cardPayload;
    if (card == null) return '数据损坏，无法还原';

    for (final col in targetBoard.columns) {
      if (col.cards.any((c) => c.id == card.id)) {
        return '卡片已存在，无法还原';
      }
    }

    var columns = [...targetBoard.columns];
    final columnId = item.columnId;
    final columnIndex =
        columnId == null ? -1 : columns.indexWhere((c) => c.id == columnId);

    if (columnIndex < 0) {
      columns.add(
        KanbanColumn(
          id: columnId ?? const Uuid().v4(),
          title: item.columnTitle ?? '已恢复的列',
          order: columns.length,
          cards: [card],
        ),
      );
    } else {
      final col = columns[columnIndex];
      columns[columnIndex] = col.copyWith(cards: [...col.cards, card]);
    }

    await _saveBoardForProject(
      projectId,
      _bump(targetBoard.copyWith(columns: columns)),
      isActive,
    );
    await _removeTrashItem(item);
    return null;
  }

  Future<String?> _restoreColumnToBoard(
    String projectId,
    KanbanBoard targetBoard,
    TrashItem item,
    bool isActive,
  ) async {
    final payload = item.columnPayload;
    if (payload == null) return '数据损坏，无法还原';

    var column = payload;
    var columns = [...targetBoard.columns];
    if (columns.any((c) => c.id == column.id)) {
      column = column.copyWith(
        id: const Uuid().v4(),
        order: columns.length,
      );
    }

    final insertAt = column.order.clamp(0, columns.length);
    columns.insert(insertAt, column);
    for (var i = 0; i < columns.length; i++) {
      columns[i] = columns[i].copyWith(order: i);
    }

    await _saveBoardForProject(
      projectId,
      _bump(targetBoard.copyWith(columns: columns)),
      isActive,
    );
    await _removeTrashItem(item);
    return null;
  }

  Future<void> _saveBoardForProject(
    String projectId,
    KanbanBoard next,
    bool isActive,
  ) async {
    return _withBoardMutation(() async {
      await _repository.saveBoard(projectId, next);
      if (isActive) {
        board = next;
        await _updateManifestEntry(title: next.title);
      }
      notifyListeners();
      _markWorkspaceChanged();
    });
  }

  Future<void> _deleteTrashItemAttachments(TrashItem item) async {
    final store = attachmentStore;
    final projectId = item.projectId;
    if (store == null || projectId == null) return;

    final card = item.cardPayload;
    if (card != null) {
      await store.deleteAttachments(
        projectId: projectId,
        attachments: card.attachments,
      );
      await store.deleteFileAttachments(
        projectId: projectId,
        attachments: card.fileAttachments,
      );
      return;
    }

    final column = item.columnPayload;
    if (column != null) {
      for (final columnCard in column.cards) {
        await store.deleteAttachments(
          projectId: projectId,
          attachments: columnCard.attachments,
        );
        await store.deleteFileAttachments(
          projectId: projectId,
          attachments: columnCard.fileAttachments,
        );
      }
      return;
    }

    final project = item.projectPayload;
    if (project != null) {
      final refs = collectReferencedAttachmentsByKind(
        project.board,
        project.projectTrash,
        settings: project.settings,
      );
      for (final id in refs.imageIds) {
        await store.deleteAttachment(projectId: projectId, attachmentId: id);
      }
      for (final id in refs.fileIds) {
        await store.deleteFileAttachment(
            projectId: projectId, attachmentId: id);
      }
    }
  }

  Future<void> _removeTrashItem(TrashItem item) async {
    final projectId = item.projectId;
    if (projectId == null) return;

    final bin = projectTrashes[projectId] ?? TrashBin.empty;
    final next = bin.bump().copyWith(
          items: bin.items.where((i) => i.id != item.id).toList(),
        );
    projectTrashes[projectId] = next;
    if (projectId == activeProjectId) {
      activeProjectTrash = next;
    }
    await _repository.saveProjectTrash(projectId, next);
    notifyListeners();
    _markWorkspaceChanged();
  }
}
