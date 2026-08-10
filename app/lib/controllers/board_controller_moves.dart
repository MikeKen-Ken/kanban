part of 'board_controller.dart';

extension BoardControllerMoves on BoardController {

  /// 将卡片从源项目转移到目标项目（默认落入目标「待办」列）。
  ///
  /// 成功返回 `null`，失败返回简体中文错误说明。
  /// [sourceProjectId] 省略时使用界面当前项目（[uiActiveProjectId]）。
  /// [targetColumnId] 省略时按 [resolveTransferTargetColumnId] 解析
  ///（优先源列同名标题，否则待办，再兜底）。
  Future<String?> transferCardToProject({
    required String fromColumnId,
    required String cardId,
    required String targetProjectId,
    String? sourceProjectId,
    String? targetColumnId,
  }) async {
    return _withBoardMutation(() async {
      final fromProjectId =
          sourceProjectId ?? _uiActiveProjectId ?? activeProjectId;
      if (fromProjectId == null) return '看板未就绪';
      if ((manifest?.projects.length ?? 0) <= 1) {
        return '没有其他可转移的项目';
      }
      if (targetProjectId == fromProjectId) return '不能转移到当前项目';
      if (manifest?.findById(targetProjectId) == null) {
        return '目标项目不存在';
      }
      if (manifest?.findById(fromProjectId) == null) {
        return '源项目不存在';
      }

      final fromBoard = await _loadBoardForTransfer(fromProjectId);
      if (fromBoard == null) return '无法加载源项目';

      KanbanCard? moving;
      for (final col in fromBoard.columns) {
        if (col.id != fromColumnId) continue;
        for (final card in col.cards) {
          if (card.id == cardId) {
            moving = card;
            break;
          }
        }
      }
      if (moving == null) return '卡片不存在';

      final toBoardLoaded = await _loadBoardForTransfer(targetProjectId);
      if (toBoardLoaded == null) return '无法加载目标项目';

      final toSettings = targetProjectId == activeProjectId
          ? projectSettings
          : await _repository.loadProjectSettings(targetProjectId);
      String? sourceColumnTitle;
      for (final col in fromBoard.columns) {
        if (col.id == fromColumnId) {
          sourceColumnTitle = col.title;
          break;
        }
      }
      final resolvedTargetColumnId = targetColumnId ??
          resolveTransferTargetColumnId(
            toBoardLoaded,
            sourceColumnTitle: sourceColumnTitle,
            doneColumnName: toSettings.doneColumnName,
          );
      if (resolvedTargetColumnId == null) return '目标项目没有可用列';
      if (!toBoardLoaded.columns.any((c) => c.id == resolvedTargetColumnId)) {
        return '目标列不存在';
      }
      if (toBoardLoaded.columns
          .any((c) => c.cards.any((card) => card.id == cardId))) {
        return '目标项目已存在相同卡片';
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final targetDone = findDoneColumn(
        toBoardLoaded,
        doneColumnName: toSettings.doneColumnName,
      );
      final landingOnDone = targetDone?.id == resolvedTargetColumnId;
      final targetColumn = toBoardLoaded.columns
          .firstWhere((c) => c.id == resolvedTargetColumnId);

      final transferred = moving.copyWith(
        order: targetColumn.cards.length,
        updatedAt: now,
        completed: landingOnDone,
        completedAt: landingOnDone ? (moving.completedAt ?? now) : null,
        // 依赖/关联指向源项目内卡片，跨项目后清空避免悬空引用
        blockedByIds: const [],
        relatedIds: const [],
        clearConflict: true,
      );

      final copyError = await _copyCardAttachmentsBetweenProjects(
        fromProjectId: fromProjectId,
        toProjectId: targetProjectId,
        attachments: moving.attachments,
      );
      if (copyError != null) return copyError;

      final fromPrefs = fromProjectId == activeProjectId
          ? columnPreferencesFor(fromColumnId)
          : (await _repository.loadProjectSettings(fromProjectId))
              .columnPreferencesFor(fromColumnId);
      final nextFromPinned = [...fromPrefs.pinnedCardIds]..remove(cardId);
      if (nextFromPinned.length != fromPrefs.pinnedCardIds.length) {
        await _updateColumnPinnedForProject(
          projectId: fromProjectId,
          columnId: fromColumnId,
          pinnedCardIds: nextFromPinned,
        );
      }

      final nextFromColumns = fromBoard.columns.map((col) {
        if (col.id != fromColumnId) return col;
        return col.copyWith(
          cards: col.cards.where((c) => c.id != cardId).toList(),
        );
      }).toList();
      await _writeBoardForTransfer(
        fromProjectId,
        _bump(fromBoard.copyWith(columns: nextFromColumns)),
      );

      final nextToColumns = toBoardLoaded.columns.map((col) {
        if (col.id != resolvedTargetColumnId) return col;
        return col.copyWith(cards: [...col.cards, transferred]);
      }).toList();
      await _writeBoardForTransfer(
        targetProjectId,
        _bump(toBoardLoaded.copyWith(columns: nextToColumns)),
      );

      final store = attachmentStore;
      if (store != null && moving.attachments.isNotEmpty) {
        await store.deleteAttachments(
          projectId: fromProjectId,
          attachments: moving.attachments,
        );
      }

      await _reminderScheduler.cancel(cardId);
      if (transferred.reminderAt != null && !transferred.completed) {
        await _scheduleCardReminder(
          projectId: targetProjectId,
          columnId: resolvedTargetColumnId,
          card: transferred,
        );
      }

      final targetTitle =
          manifest?.findById(targetProjectId)?.title ?? targetProjectId;
      final sourceTitle =
          manifest?.findById(fromProjectId)?.title ?? fromProjectId;
      await _recordActivity(
        entityId: cardId,
        entityTitle: moving.title,
        action: ActivityAction.moved,
        details: {
          'transfer': 'project',
          'fromProjectId': fromProjectId,
          'toProjectId': targetProjectId,
          'fromColumnId': fromColumnId,
          'toColumnId': resolvedTargetColumnId,
          'fromProjectTitle': sourceTitle,
          'toProjectTitle': targetTitle,
        },
      );

      _pushUndo(
        '转移「${moving.title}」到「$targetTitle」',
        () async {
          final error = await transferCardToProject(
            fromColumnId: resolvedTargetColumnId,
            cardId: cardId,
            targetProjectId: fromProjectId,
            sourceProjectId: targetProjectId,
            targetColumnId: fromColumnId,
          );
          if (error != null) throw StateError(error);
        },
        redo: () async {
          final error = await transferCardToProject(
            fromColumnId: fromColumnId,
            cardId: cardId,
            targetProjectId: targetProjectId,
            sourceProjectId: fromProjectId,
            targetColumnId: resolvedTargetColumnId,
          );
          if (error != null) throw StateError(error);
        },
      );

      return null;
    });
  }

  Future<KanbanBoard?> _loadBoardForTransfer(String projectId) async {
    if (projectId == activeProjectId) return board;
    if (projectId == _uiActiveProjectId) return _uiBoard;
    return _repository.loadBoard(projectId);
  }

  Future<void> _writeBoardForTransfer(
    String projectId,
    KanbanBoard next,
  ) async {
    await _repository.saveBoard(projectId, next);
    if (_projectMutationScope != null &&
        projectId == _projectMutationScope!.projectId) {
      board = next;
    } else if (projectId == _uiActiveProjectId) {
      _uiBoard = next;
    }
    notifyListeners();
    _markWorkspaceChanged();
  }

  Future<String?> _copyCardAttachmentsBetweenProjects({
    required String fromProjectId,
    required String toProjectId,
    required List<CardAttachment> attachments,
  }) async {
    if (attachments.isEmpty) return null;
    final store = attachmentStore;
    if (store == null) return null;
    try {
      for (final attachment in attachments) {
        final bytes = await store.readBytes(
          projectId: fromProjectId,
          attachmentId: attachment.id,
        );
        if (bytes != null) {
          await store.writeBytes(
            projectId: toProjectId,
            attachmentId: attachment.id,
            bytes: bytes,
          );
        }
        final thumb = await store.readBytes(
          projectId: fromProjectId,
          attachmentId: attachment.id,
          thumb: true,
        );
        if (thumb != null) {
          await store.writeBytes(
            projectId: toProjectId,
            attachmentId: attachment.id,
            bytes: thumb,
            thumb: true,
          );
        }
      }
    } catch (error) {
      debugPrint('转移卡片附件失败：$error');
      return '转移附件失败';
    }
    return null;
  }

  Future<void> _updateColumnPinnedForProject({
    required String projectId,
    required String columnId,
    required List<String> pinnedCardIds,
  }) async {
    if (projectId == activeProjectId) {
      final prefs = columnPreferencesFor(columnId);
      await _persistProjectSettings(
        projectSettings.bump().copyWith(
          columnPreferences: {
            ...projectSettings.columnPreferences,
            columnId: prefs.copyWith(pinnedCardIds: pinnedCardIds),
          },
        ),
      );
      return;
    }
    final settings = await _repository.loadProjectSettings(projectId);
    final prefs = settings.columnPreferencesFor(columnId);
    final next = settings.bump().copyWith(
      columnPreferences: {
        ...settings.columnPreferences,
        columnId: prefs.copyWith(pinnedCardIds: pinnedCardIds),
      },
    );
    await _repository.saveProjectSettings(projectId, next);
    _markWorkspaceChanged();
  }

  /// 清空已完成列中的全部卡片（移入回收站）。仅当 [columnId] 为当前项目的已完成列时生效。
  /// 返回实际清空的卡片数量。
  Future<int> clearDoneColumnCards(String columnId) async {
    return _withBoardMutation(() async {
      if (board == null || activeProjectId == null) return 0;

      final doneColumn = _findDoneColumn(board!);
      if (doneColumn == null || doneColumn.id != columnId) return 0;
      if (doneColumn.cards.isEmpty) return 0;

      final now = DateTime.now().millisecondsSinceEpoch;
      final trashIds = <String>[];
      final newTrashItems = <TrashItem>[];
      final clearedCards = List<KanbanCard>.from(doneColumn.cards);

      for (final card in clearedCards) {
        final trashId = const Uuid().v4();
        trashIds.add(trashId);
        newTrashItems.add(
          TrashItem.forCard(
            trashId: trashId,
            deletedAt: now,
            projectId: activeProjectId!,
            projectTitle: board!.title,
            columnId: columnId,
            columnTitle: doneColumn.title,
            card: card,
          ),
        );
      }

      activeProjectTrash = activeProjectTrash.bump().copyWith(
        items: [...newTrashItems, ...activeProjectTrash.items],
      );
      await _persistActiveProjectTrash();

      final columns = board!.columns.map((col) {
        if (col.id != columnId) return col;
        return col.copyWith(cards: const <KanbanCard>[]);
      }).toList();
      await _persistAndSync(_bump(board!.copyWith(columns: columns)));

      for (final card in clearedCards) {
        await _reminderScheduler.cancel(card.id);
        await _recordActivity(
          entityId: card.id,
          entityTitle: card.title,
          action: ActivityAction.deleted,
        );
      }

      final count = clearedCards.length;
      final clearedCardIds = [for (final card in clearedCards) card.id];
      var currentTrashIds = List<String>.from(trashIds);
      _pushUndo(
        '清空「${doneColumn.title}」($count)',
        () async {
          for (final trashId in currentTrashIds.reversed) {
            final error = await restoreTrashItem(trashId);
            if (error != null) throw StateError(error);
          }
        },
        redo: () async {
          final nextIds = <String>[];
          for (final cardId in clearedCardIds) {
            final id = await deleteCard(columnId, cardId);
            if (id != null) nextIds.add(id);
          }
          currentTrashIds = nextIds;
        },
      );
      return count;
    });
  }

  /// 扫描全部项目，将超过保留天数的已完成列卡片移入回收站。
  ///
  /// [force] 为 true 时忽略节流（例如用户刚改了保留天数）。
  /// 返回实际移入回收站的卡片数量。
  Future<int> purgeExpiredCompletedCards({bool force = false}) async {
    final days = appSettings.completedAutoClearDays;
    if (days <= 0) return 0;
    if (isLoading || errorMessage != null) return 0;
    if (_completedAutoClearRunning) return 0;

    final now = DateTime.now();
    if (!force) {
      final last = _lastCompletedAutoClearAt;
      if (last != null &&
          now.difference(last) < completedAutoClearMinInterval) {
        return 0;
      }
    }

    _completedAutoClearRunning = true;
    _lastCompletedAutoClearAt = now;
    var total = 0;
    try {
      final projects =
          List<ProjectEntry>.from(manifest?.projects ?? const <ProjectEntry>[]);
      for (final entry in projects) {
        try {
          total += await runOnProject(
            entry.id,
            () => _purgeExpiredCompletedInCurrentProject(days, now),
          );
        } catch (error) {
          debugPrint('自动清空已完成失败（${entry.title}）：$error');
        }
      }
      if (total > 0) {
        debugPrint('自动清空已完成：$total 张卡片已移入回收站');
      }
      return total;
    } finally {
      _completedAutoClearRunning = false;
    }
  }

  Future<int> _purgeExpiredCompletedInCurrentProject(
    int days,
    DateTime now,
  ) async {
    final current = board;
    final projectId = activeProjectId;
    if (current == null || projectId == null) return 0;

    final expired = selectExpiredCompletedCards(
      board: current,
      doneColumnName: projectSettings.doneColumnName,
      retainDays: days,
      now: now,
    );
    if (expired.isEmpty) return 0;

    final doneColumn = findDoneColumn(
      current,
      doneColumnName: projectSettings.doneColumnName,
    );
    if (doneColumn == null) return 0;

    final expiredIds = {for (final card in expired) card.id};
    final deletedAt = now.millisecondsSinceEpoch;
    final newTrashItems = <TrashItem>[
      for (final card in expired)
        TrashItem.forCard(
          trashId: const Uuid().v4(),
          deletedAt: deletedAt,
          projectId: projectId,
          projectTitle: current.title,
          columnId: doneColumn.id,
          columnTitle: doneColumn.title,
          card: card,
        ),
    ];

    activeProjectTrash = activeProjectTrash.bump().copyWith(
      items: [...newTrashItems, ...activeProjectTrash.items],
    );
    await _persistActiveProjectTrash();

    final columns = current.columns.map((col) {
      if (col.id != doneColumn.id) return col;
      return col.copyWith(
        cards: [
          for (final card in col.cards)
            if (!expiredIds.contains(card.id)) card,
        ],
      );
    }).toList();
    await _persistAndSync(_bump(current.copyWith(columns: columns)));

    for (final card in expired) {
      await _reminderScheduler.cancel(card.id);
      await _recordActivity(
        entityId: card.id,
        entityTitle: card.title,
        action: ActivityAction.deleted,
        source: ActivitySource.automation,
      );
    }
    return expired.length;
  }

  /// 移动卡片。规则门禁拒绝时返回简体中文原因，成功返回 `null`。
  Future<String?> moveCard({
    required String cardId,
    required String fromColumnId,
    required String toColumnId,
    required int toDisplayIndex,
    bool? completed,
    int? completedAt,
  }) async {
    return _withBoardMutation(() async {
      if (board == null) return null;

      final now = DateTime.now().millisecondsSinceEpoch;
      final fromPrefs = columnPreferencesFor(fromColumnId);
      final toPrefs = columnPreferencesFor(toColumnId);

      if (fromColumnId == toColumnId &&
          fromPrefs.sortMode != CardSortMode.custom) {
        return null;
      }

      KanbanCard? moving;
      final stripped = board!.columns.map((col) {
        if (col.id != fromColumnId) return col;
        final remaining = <KanbanCard>[];
        for (final card in col.cards) {
          if (card.id == cardId) {
            moving = card;
          } else {
            remaining.add(card);
          }
        }
        return col.copyWith(cards: remaining);
      }).toList();

      if (moving == null) return null;

      final reworkRejection = reworkMoveRejectionReason(
        fromColumnId: fromColumnId,
        toColumnId: toColumnId,
        verificationFeedback: moving!.verificationFeedback,
        columns: board!.columns,
        doneColumnName: projectSettings.doneColumnName,
      );
      if (reworkRejection != null) return reworkRejection;

      final doneColumn = _findDoneColumn(board!);
      var cardToInsert = moving!;
      if (completed != null) {
        cardToInsert = cardToInsert.copyWith(
          completed: completed,
          completedAt: completedAt,
          updatedAt: now,
        );
      } else if (doneColumn != null) {
        final markDone = toColumnId == doneColumn.id;
        cardToInsert = cardToInsert.copyWith(
          completed: markDone,
          completedAt: markDone ? (cardToInsert.completedAt ?? now) : null,
          updatedAt: now,
        );
      } else {
        cardToInsert = cardToInsert.copyWith(updatedAt: now);
      }

      var nextPinnedByColumn = Map<String, ColumnCardPreferences>.from(
        projectSettings.columnPreferences,
      );

      if (fromColumnId != toColumnId) {
        final fromPinned = [...fromPrefs.pinnedCardIds]..remove(cardId);
        nextPinnedByColumn[fromColumnId] =
            fromPrefs.copyWith(pinnedCardIds: fromPinned);
      }

      final inserted = stripped.map((col) {
        if (col.id != toColumnId) return col;

        if (toPrefs.sortMode != CardSortMode.custom) {
          final cards = [
            ...col.cards,
            cardToInsert.copyWith(order: col.cards.length),
          ];
          return col.copyWith(cards: cards);
        }

        final targetPinned = nextPinnedByColumn[toColumnId]?.pinnedCardIds ??
            toPrefs.pinnedCardIds;
        final pinnedCount = pinnedCardCount(targetPinned, col.cards);
        var display = sortColumnCards(
          col.cards,
          sortMode: CardSortMode.custom,
          pinnedCardIds: targetPinned,
        );

        var index = toDisplayIndex.clamp(0, display.length);
        final movingPinned = targetPinned.contains(cardId);
        if (movingPinned) {
          index = index.clamp(0, pinnedCount);
        } else {
          index = index.clamp(pinnedCount, display.length);
        }

        if (fromColumnId == toColumnId) {
          final before = sortColumnCards(
            [...col.cards, cardToInsert],
            sortMode: CardSortMode.custom,
            pinnedCardIds: targetPinned,
          );
          final oldIndex = before.indexWhere((card) => card.id == cardId);
          if (oldIndex >= 0 && oldIndex < index) {
            index -= 1;
          }
        }

        display = [...display]..insert(index, cardToInsert);
        final derived = _pinnedAndOrdersFromDisplay(display, targetPinned);
        final cards = _applyPinnedAndOrders(
          [
            ...col.cards.where((card) => card.id != cardId),
            cardToInsert,
          ],
          derived.orders,
          now,
          cardId,
        );

        nextPinnedByColumn[toColumnId] =
            (nextPinnedByColumn[toColumnId] ?? toPrefs)
                .copyWith(pinnedCardIds: derived.pinned);

        return col.copyWith(cards: cards);
      }).toList();

      if (nextPinnedByColumn != projectSettings.columnPreferences) {
        projectSettings = projectSettings.bump().copyWith(
              columnPreferences: nextPinnedByColumn,
            );
        if (activeProjectId != null) {
          await _repository.saveProjectSettings(
              activeProjectId!, projectSettings);
        }
      }

      await _persistAndSync(
        _bump(board!.copyWith(columns: _normalizeOrders(inserted))),
      );
      if (fromColumnId != toColumnId) {
        final originalIndex = moving!.order;
        if (!_applyingAutomation) {
          _pushUndo(
            '移动「${moving!.title}」',
            () => moveCard(
              cardId: cardId,
              fromColumnId: toColumnId,
              toColumnId: fromColumnId,
              toDisplayIndex: originalIndex,
            ),
            redo: () => moveCard(
              cardId: cardId,
              fromColumnId: fromColumnId,
              toColumnId: toColumnId,
              toDisplayIndex: toDisplayIndex,
              completed: completed,
              completedAt: completedAt,
            ),
          );
        }
        await _recordActivity(
          entityId: cardId,
          entityTitle: moving!.title,
          action: ActivityAction.moved,
          details: {
            'fromColumnId': fromColumnId,
            'toColumnId': toColumnId,
          },
        );
        if (!_applyingAutomation) {
          final card = findCardById(cardId);
          if (card != null) {
            await _runAutomations(
              _BoardControllerBase._automationEngine.effectsForMove(
                rules: projectSettings.automationRules,
                toColumnId: toColumnId,
                card: card,
              ),
              columnId: toColumnId,
              cardId: cardId,
            );
          }
        }
      }
      return null;
    });
  }
}

