part of 'board_controller.dart';

extension BoardControllerSync on BoardController {
  Future<void> saveWebDavConfig(WebDavConfig config) async {
    final connected = config.enabled && config.isConfigured;
    await _withBoardMutation(() async {
      webDavConfig = config;
      await _repository.saveWebDavConfig(config);
      // 仅自动拉取开启时挂后台轮询；保存配置本身不触发同步
      if (connected && config.autoPull) {
        _syncService.startPolling();
      } else {
        _syncService.stopPolling();
      }
      notifyListeners();
    });
    unawaited(_syncService.refreshPendingUploadCount());
  }

  Future<bool> testWebDav(WebDavConfig config) {
    return _syncService.testConnection(config);
  }

  Future<void> syncNow() async {
    await _syncService.pullAndMerge(userInitiated: true);
  }

  /// 取消进行中的 WebDAV 同步，恢复可继续操作
  bool cancelSync() {
    return _syncService.cancelSync();
  }

  /// 解决单卡冲突：保留主副本或另一侧
  Future<void> resolveCardConflict(
    String columnId,
    String cardId,
    CardConflictResolution resolution,
  ) async {
    return _withBoardMutation(() async {
      if (board == null) return;

      KanbanCard? target;
      String? targetColumnId;
      for (final col in board!.columns) {
        for (final card in col.cards) {
          if (card.id == cardId) {
            target = card;
            targetColumnId = col.id;
            break;
          }
        }
        if (target != null) break;
      }
      if (target == null || !target.hasConflict) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      late KanbanCard resolved;
      var resolvedColumnId = targetColumnId!;

      if (resolution == CardConflictResolution.keepPrimary) {
        if (target.conflictDeleted) {
          // note: 主侧是「仍存在」版本，选择主侧即保留卡片并清除删除冲突
          resolved = target.copyWith(clearConflict: true, updatedAt: now);
        } else {
          resolved = target.copyWith(clearConflict: true, updatedAt: now);
        }
      } else {
        if (target.conflictDeleted) {
          // 选择另一侧删除意图与普通删除一致，保留可恢复快照。
          await deleteCard(targetColumnId, cardId);
          return;
        }
        final other = target.conflictSide;
        if (other == null) return;
        resolved = other.copyWith(clearConflict: true, updatedAt: now);
        resolvedColumnId = target.conflictColumnId ?? targetColumnId;
      }

      var columns = board!.columns.map((col) {
        return col.copyWith(
          cards: col.cards.where((c) => c.id != cardId).toList(),
        );
      }).toList();

      columns = columns.map((col) {
        if (col.id != resolvedColumnId) return col;
        final cards = [...col.cards, resolved]
          ..sort((a, b) => a.order.compareTo(b.order));
        return col.copyWith(cards: cards);
      }).toList();

      // 若目标列不存在，放回原列
      if (!columns.any((c) => c.id == resolvedColumnId)) {
        columns = columns.map((col) {
          if (col.id != targetColumnId) return col;
          return col.copyWith(cards: [...col.cards, resolved]);
        }).toList();
      }

      await _persistAndSync(_bump(board!.copyWith(columns: columns)));
    });
  }

  Future<void> resolveSettingsConflict({required bool keepPrimary}) async {
    return _withBoardMutation(() async {
      if (!projectSettings.hasConflict) return;
      final next = keepPrimary
          ? projectSettings.copyWith(clearConflictSide: true)
          : (projectSettings.conflictSide ?? projectSettings)
              .copyWith(clearConflictSide: true);
      await _persistProjectSettings(next.bump());
    });
  }

  /// 解决当前看板的标题冲突。
  Future<void> resolveBoardTitleConflict({required bool keepPrimary}) async {
    return _withBoardMutation(() async {
      final current = board;
      if (current == null || current.conflictTitle == null) return;
      final title = keepPrimary ? current.title : current.conflictTitle!;
      await _persistAndSync(
        _bump(
          current.copyWith(
            title: title,
            clearConflictTitle: true,
          ),
        ),
      );
    });
  }

  /// 解决项目清单条目的标题冲突。
  Future<void> resolveProjectTitleConflict(
    String projectId, {
    required bool keepPrimary,
  }) async {
    return _withBoardMutation(() async {
      final entry = manifest?.findById(projectId);
      if (entry == null || entry.conflictTitle == null) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final title = keepPrimary ? entry.title : entry.conflictTitle!;
      final projects = manifest!.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          title: title,
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

  /// 解决项目删改冲突：保留项目或确认删除
  Future<void> resolveProjectConflict(
    String projectId, {
    required bool keepProject,
  }) async {
    return _withBoardMutation(() async {
      if (manifest == null) return;
      final entry = manifest!.findById(projectId);
      if (entry == null || !entry.conflictDeleted) return;

      if (!keepProject) {
        await deleteProject(projectId);
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final projects = manifest!.projects.map((p) {
        if (p.id != projectId) return p;
        return p.copyWith(
          clearConflict: true,
          updatedAt: now,
          revision: p.revision + 1,
        );
      }).toList();
      manifest = manifest!.bump().copyWith(projects: projects);
      await _repository.saveManifest(manifest!);
      notifyListeners();
      _markWorkspaceChanged();
    });
  }
}

