part of 'board_controller.dart';

extension BoardControllerCards on BoardController {
  Future<String?> addCard(
    String columnId,
    String title, {
    String? description,
    int? dueDate,
    int? reminderAt,
    CardRecurrence recurrence = CardRecurrence.none,
    CardPriority priority = CardPriority.none,
    List<String> labels = const [],
  }) async {
    return _withBoardMutation(() async {
      if (board == null) return null;
      final landingColumnId = resolveColumnIdForNeedResourceLabels(
        preferredColumnId: columnId,
        labels: labels,
        columns: board!.columns,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final cardId = const Uuid().v4();
      var added = false;
      final columns = board!.columns.map((col) {
        if (col.id != landingColumnId) return col;
        added = true;
        final cards = [
          ...col.cards,
          KanbanCard(
            id: cardId,
            title: title,
            description: description,
            order: col.cards.length,
            createdAt: now,
            updatedAt: now,
            dueDate: dueDate,
            reminderAt: reminderAt,
            recurrence: recurrence,
            recurrenceSeriesId:
                recurrence == CardRecurrence.none ? null : cardId,
            priority: priority,
            labels: labels,
          ),
        ];
        return col.copyWith(cards: cards);
      }).toList();
      if (!added) return null;
      await _persistAndSync(_bump(board!.copyWith(columns: columns)));
      String? trashId;
      _pushUndo(
        '新建「$title」',
        () async {
          trashId = await deleteCard(landingColumnId, cardId);
        },
        redo: () async {
          final id = trashId;
          if (id == null) return;
          final error = await restoreTrashItem(id);
          if (error != null) throw StateError(error);
        },
      );
      if (reminderAt != null && activeProjectId != null) {
        await _scheduleCardReminder(
          projectId: activeProjectId!,
          columnId: landingColumnId,
          card: columns
              .firstWhere((column) => column.id == landingColumnId)
              .cards
              .firstWhere((card) => card.id == cardId),
        );
      }
      await _recordActivity(
        entityId: cardId,
        entityTitle: title,
        action: ActivityAction.created,
      );
      return cardId;
    });
  }

  /// 在同一列克隆整张卡片；新卡片使用独立的标识、重复系列和附件文件。
  Future<String?> duplicateCard(String columnId, String cardId) async {
    return _withBoardMutation(() async {
      if (board == null) return null;
      final sourceColumn =
          board!.columns.where((column) => column.id == columnId).firstOrNull;
      if (sourceColumn == null) return null;
      final source =
          sourceColumn.cards.where((card) => card.id == cardId).firstOrNull;
      if (source == null) return null;

      final now = DateTime.now().millisecondsSinceEpoch;
      final duplicatedId = const Uuid().v4();
      final copiedAttachments = await _copyCardAttachments(source.attachments);
      final copiedFileAttachments =
          await _copyCardFileAttachments(source.fileAttachments);
      final duplicated = source.copyWith(
        id: duplicatedId,
        order: sourceColumn.cards.length,
        createdAt: now,
        updatedAt: now,
        recurrenceSeriesId:
            source.recurrence == CardRecurrence.none ? null : duplicatedId,
        checklist: [
          for (final item in source.checklist)
            item.copyWith(id: const Uuid().v4()),
        ],
        verificationFeedback: [
          for (final item in source.verificationFeedback)
            item.copyWith(id: const Uuid().v4()),
        ],
        attachments: copiedAttachments,
        fileAttachments: copiedFileAttachments,
        links: [
          for (final link in source.links)
            link.copyWith(id: const Uuid().v4(), createdAt: now),
        ],
        clearConflict: true,
      );
      final columns = board!.columns.map((column) {
        if (column.id != columnId) return column;
        return column.copyWith(cards: [...column.cards, duplicated]);
      }).toList();
      await _persistAndSync(_bump(board!.copyWith(columns: columns)));

      String? trashId;
      _pushUndo(
        '克隆「${source.title}」',
        () async {
          trashId = await deleteCard(columnId, duplicatedId);
        },
        redo: () async {
          final id = trashId;
          if (id == null) return;
          final error = await restoreTrashItem(id);
          if (error != null) throw StateError(error);
        },
      );
      if (duplicated.reminderAt != null && activeProjectId != null) {
        await _scheduleCardReminder(
          projectId: activeProjectId!,
          columnId: columnId,
          card: duplicated,
        );
      }
      await _recordActivity(
        entityId: duplicatedId,
        entityTitle: duplicated.title,
        action: ActivityAction.created,
      );
      await refreshMissingAttachments();
      return duplicatedId;
    });
  }

  /// 为副本生成独立附件，避免删除或同步其中一张卡片时影响原卡片。
  Future<List<CardAttachment>> _copyCardAttachments(
    List<CardAttachment> sourceAttachments,
  ) async {
    final store = attachmentStore;
    final projectId = activeProjectId;
    if (store == null || projectId == null || sourceAttachments.isEmpty) {
      return const [];
    }

    final orderedAttachments = [...sourceAttachments]
      ..sort((a, b) => a.order.compareTo(b.order));
    final copied = <CardAttachment>[];
    for (final attachment in orderedAttachments) {
      try {
        final bytes = await store.readBytes(
          projectId: projectId,
          attachmentId: attachment.id,
          thumb: false,
        );
        if (bytes == null) continue;
        copied.add(
          await store.saveImage(
            projectId: projectId,
            sourceBytes: bytes,
            fileName: attachment.fileName,
            order: copied.length,
          ),
        );
      } catch (error) {
        debugPrint('复制卡片附件失败：$error');
      }
    }
    return copied;
  }

  Future<void> updateCard(
    String columnId,
    String cardId, {
    String? title,
    String? description,
  }) async {
    await updateCardFull(
      columnId,
      cardId,
      title: title,
      description: description,
    );
  }

  /// 更新卡片。规则门禁拒绝时返回简体中文原因，成功返回 `null`。
  Future<String?> updateCardFull(
    String columnId,
    String cardId, {
    String? title,
    String? description,
    bool clearDescription = false,
    bool? completed,
    int? dueDate,
    bool clearDueDate = false,
    int? reminderAt,
    bool clearReminder = false,
    CardRecurrence? recurrence,
    int? recurrenceInterval,
    CardPriority? priority,
    List<String>? labels,
    List<ChecklistItem>? checklist,
    List<ChecklistItem>? verificationFeedback,
    List<CardAttachment>? attachments,
    List<CardFileAttachment>? fileAttachments,
    List<CardLink>? links,
    List<String>? blockedByIds,
    List<String>? relatedIds,
    String? commitRef,
    bool clearCommitRef = false,
    int? colorValue,
    bool clearColor = false,
  }) async {
    return _withBoardMutation(() async {
      if (board == null) return null;
      final now = DateTime.now().millisecondsSinceEpoch;
      final original = board!.columns
          .where((column) => column.id == columnId)
          .expand((column) => column.cards)
          .where((card) => card.id == cardId)
          .firstOrNull;
      if (original == null) return null;
      final nextVerificationFeedback =
          verificationFeedback ?? original.verificationFeedback;
      if (completed == true &&
          hasIncompleteVerificationFeedback(nextVerificationFeedback)) {
        return incompleteVerificationFeedbackBlocksProgressMessage;
      }
      // 未完成反馈是流程权威状态：即使旧数据已完成，也必须恢复未完成态。
      final nextCompleted = hasIncompleteVerificationFeedback(
        nextVerificationFeedback,
      )
          ? false
          : (completed ?? original.completed);
      final columns = board!.columns.map((col) {
        if (col.id != columnId) return col;
        final cards = col.cards.map((card) {
          if (card.id != cardId) return card;
          return card.copyWith(
            title: title ?? card.title,
            description:
                clearDescription ? null : (description ?? card.description),
            completed: nextCompleted,
            completedAt: nextCompleted ? (card.completedAt ?? now) : null,
            dueDate: clearDueDate ? null : (dueDate ?? card.dueDate),
            reminderAt: clearReminder ? null : (reminderAt ?? card.reminderAt),
            recurrence: recurrence ?? card.recurrence,
            recurrenceInterval: recurrenceInterval ?? card.recurrenceInterval,
            priority: priority ?? card.priority,
            labels: labels ?? card.labels,
            checklist: checklist ?? card.checklist,
            verificationFeedback: nextVerificationFeedback,
            attachments: attachments ?? card.attachments,
            fileAttachments: fileAttachments ?? card.fileAttachments,
            links: links ?? card.links,
            blockedByIds: blockedByIds ?? card.blockedByIds,
            relatedIds: relatedIds ?? card.relatedIds,
            commitRef: clearCommitRef
                ? null
                : (commitRef ?? card.commitRef),
            colorValue: clearColor ? null : (colorValue ?? card.colorValue),
            updatedAt: now,
          );
        }).toList();
        return col.copyWith(cards: cards);
      }).toList();
      await _persistAndSync(
        _bump(board!.copyWith(columns: _normalizeOrders(columns))),
      );
      if (!_applyingAutomation) {
        final restoredTitle = title ?? original.title;
        final restoredDescription =
            clearDescription ? null : (description ?? original.description);
        final restoredCompleted = nextCompleted;
        final restoredDueDate =
            clearDueDate ? null : (dueDate ?? original.dueDate);
        final restoredReminderAt =
            clearReminder ? null : (reminderAt ?? original.reminderAt);
        final restoredRecurrence = recurrence ?? original.recurrence;
        final restoredRecurrenceInterval =
            recurrenceInterval ?? original.recurrenceInterval;
        final restoredPriority = priority ?? original.priority;
        final restoredLabels = labels ?? original.labels;
        final restoredChecklist = checklist ?? original.checklist;
        final restoredVerification =
            verificationFeedback ?? original.verificationFeedback;
        final restoredAttachments = attachments ?? original.attachments;
        final restoredFileAttachments =
            fileAttachments ?? original.fileAttachments;
        final restoredLinks = links ?? original.links;
        final restoredBlockedBy = blockedByIds ?? original.blockedByIds;
        final restoredRelated = relatedIds ?? original.relatedIds;
        final restoredCommitRef = clearCommitRef
            ? null
            : (commitRef ?? original.commitRef);
        final restoredColor =
            clearColor ? null : (colorValue ?? original.colorValue);
        _pushUndo(
          '编辑「${original.title}」',
          () async {
            final error = await updateCardFull(
              columnId,
              cardId,
              title: original.title,
              description: original.description,
              clearDescription: original.description == null,
              completed: original.completed,
              dueDate: original.dueDate,
              clearDueDate: original.dueDate == null,
              reminderAt: original.reminderAt,
              clearReminder: original.reminderAt == null,
              recurrence: original.recurrence,
              recurrenceInterval: original.recurrenceInterval,
              priority: original.priority,
              labels: original.labels,
              checklist: original.checklist,
              verificationFeedback: original.verificationFeedback,
              attachments: original.attachments,
              fileAttachments: original.fileAttachments,
              links: original.links,
              blockedByIds: original.blockedByIds,
              relatedIds: original.relatedIds,
              commitRef: original.commitRef,
              clearCommitRef: original.commitRef == null,
              colorValue: original.colorValue,
              clearColor: original.colorValue == null,
            );
            if (error != null) throw StateError(error);
          },
          redo: () async {
            final error = await updateCardFull(
              columnId,
              cardId,
              title: restoredTitle,
              description: restoredDescription,
              clearDescription: restoredDescription == null,
              completed: restoredCompleted,
              dueDate: restoredDueDate,
              clearDueDate: restoredDueDate == null,
              reminderAt: restoredReminderAt,
              clearReminder: restoredReminderAt == null,
              recurrence: restoredRecurrence,
              recurrenceInterval: restoredRecurrenceInterval,
              priority: restoredPriority,
              labels: restoredLabels,
              checklist: restoredChecklist,
              verificationFeedback: restoredVerification,
              attachments: restoredAttachments,
              fileAttachments: restoredFileAttachments,
              links: restoredLinks,
              blockedByIds: restoredBlockedBy,
              relatedIds: restoredRelated,
              commitRef: restoredCommitRef,
              clearCommitRef: restoredCommitRef == null,
              colorValue: restoredColor,
              clearColor: restoredColor == null,
            );
            if (error != null) throw StateError(error);
          },
        );
      }
      await _recordActivity(
        entityId: cardId,
        entityTitle: title ?? original.title,
        action: ActivityAction.updated,
      );
      await _rescheduleReminders();

      if (!_applyingAutomation) {
        final updated = board!.columns
            .where((column) => column.id == columnId)
            .expand((column) => column.cards)
            .where((card) => card.id == cardId)
            .firstOrNull;
        if (updated != null) {
          if (nextCompleted && !original.completed) {
            await _runAutomations(
              _BoardControllerBase._automationEngine.effectsForCompleted(
                rules: projectSettings.automationRules,
                card: updated,
              ),
              columnId: columnId,
              cardId: cardId,
            );
          }
          final checklistChanged = checklist != null;
          if (checklistChanged) {
            await _runAutomations(
              _BoardControllerBase._automationEngine.effectsForChecklistAllDone(
                rules: projectSettings.automationRules,
                card: updated,
              ),
              columnId: columnId,
              cardId: cardId,
            );
          }
        }
      }
      final nextLabels = labels ?? original.labels;
      final currentColumnId = findColumnIdForCard(cardId);
      final currentBoard = board;
      if (currentColumnId != null && currentBoard != null) {
        final blockedTargetId = targetBlockedColumnIdIfNeedResource(
          labels: nextLabels,
          currentColumnId: currentColumnId,
          columns: currentBoard.columns,
        );
        if (blockedTargetId != null) {
          final blocked = findBlockedColumn(currentBoard.columns);
          await moveCard(
            cardId: cardId,
            fromColumnId: currentColumnId,
            toColumnId: blockedTargetId,
            toDisplayIndex: blocked?.cards.length ?? 0,
          );
        } else if (hasAddedVerificationFeedbackItems(
          original: original.verificationFeedback,
          next: nextVerificationFeedback,
        )) {
          await ensureReworkColumn();
          final afterColumnId = findColumnIdForCard(cardId);
          final afterBoard = board;
          final rework = afterBoard == null
              ? null
              : findReworkColumn(afterBoard.columns);
          if (afterColumnId != null &&
              rework != null &&
              afterColumnId != rework.id) {
            await moveCard(
              cardId: cardId,
              fromColumnId: afterColumnId,
              toColumnId: rework.id,
              toDisplayIndex: rework.cards.length,
            );
          }
        }
      }
      return null;
    });
  }

  /// 按卡片 id 查找所属列。
  String? findColumnIdForCard(String cardId) {
    final current = board;
    if (current == null) return null;
    for (final column in current.columns) {
      if (column.cards.any((card) => card.id == cardId)) {
        return column.id;
      }
    }
    return null;
  }

  KanbanCard? findCardById(String cardId) {
    final current = board;
    if (current == null) return null;
    for (final column in current.columns) {
      for (final card in column.cards) {
        if (card.id == cardId) return card;
      }
    }
    return null;
  }

  /// 原子建立或解除两张卡的双向关联。
  ///
  /// 两张卡必须位于当前项目；一次落盘同时更新两侧，避免只写入单侧回链。
  Future<String?> setCardsRelated({
    required String firstCardId,
    required String secondCardId,
    required bool related,
  }) {
    return _withBoardMutation(() async {
      final firstId = firstCardId.trim();
      final secondId = secondCardId.trim();
      if (firstId.isEmpty || secondId.isEmpty) {
        return '关联卡片 id 不能为空';
      }
      if (firstId == secondId) return '卡片不能关联自身';

      final first = findCardById(firstId);
      final second = findCardById(secondId);
      if (first == null) return '卡片不存在：$firstId';
      if (second == null) return '卡片不存在：$secondId';

      List<String> nextIds(
        List<String> current,
        String selfId,
        String otherId,
      ) {
        final next = <String>[];
        for (final id in current) {
          if (id == selfId || id == otherId) continue;
          if (!next.contains(id)) next.add(id);
        }
        if (related && !next.contains(otherId)) next.add(otherId);
        return next;
      }

      final nextByCardId = <String, List<String>>{
        firstId: nextIds(first.relatedIds, firstId, secondId),
        secondId: nextIds(second.relatedIds, secondId, firstId),
      };
      final action = related ? '关联' : '解除关联';
      return _replaceCardRelatedIds(
        nextByCardId,
        undoLabel: '$action「${first.title}」与「${second.title}」',
      );
    });
  }

  Future<String?> _replaceCardRelatedIds(
    Map<String, List<String>> relatedByCardId, {
    required String undoLabel,
    bool recordUndo = true,
  }) {
    return _withBoardMutation(() async {
      final currentBoard = board;
      if (currentBoard == null) return '看板未就绪';

      final originals = <String, KanbanCard>{};
      for (final cardId in relatedByCardId.keys) {
        final card = findCardById(cardId);
        if (card == null) return '卡片不存在：$cardId';
        originals[cardId] = card;
      }
      final changedIds = originals.keys
          .where((cardId) => !listEquals(
                originals[cardId]!.relatedIds,
                relatedByCardId[cardId],
              ))
          .toList();
      if (changedIds.isEmpty) return null;

      final now = DateTime.now().millisecondsSinceEpoch;
      final columns = currentBoard.columns.map((column) {
        final cards = column.cards.map((card) {
          final relatedIds = relatedByCardId[card.id];
          if (relatedIds == null) return card;
          return card.copyWith(
            relatedIds: List<String>.from(relatedIds),
            updatedAt: now,
          );
        }).toList();
        return column.copyWith(cards: cards);
      }).toList();
      await _persistAndSync(_bump(currentBoard.copyWith(columns: columns)));

      if (recordUndo) {
        final before = <String, List<String>>{
          for (final entry in originals.entries)
            entry.key: List<String>.from(entry.value.relatedIds),
        };
        final after = <String, List<String>>{
          for (final entry in relatedByCardId.entries)
            entry.key: List<String>.from(entry.value),
        };
        _pushUndo(
          undoLabel,
          () async {
            final error = await _replaceCardRelatedIds(
              before,
              undoLabel: undoLabel,
              recordUndo: false,
            );
            if (error != null) throw StateError(error);
          },
          redo: () async {
            final error = await _replaceCardRelatedIds(
              after,
              undoLabel: undoLabel,
              recordUndo: false,
            );
            if (error != null) throw StateError(error);
          },
        );
      }

      for (final cardId in changedIds) {
        final card = originals[cardId]!;
        await _recordActivity(
          entityId: cardId,
          entityTitle: card.title,
          action: ActivityAction.updated,
          details: {'field': 'relatedIds'},
        );
      }
      return null;
    });
  }

  Future<void> _runAutomations(
    List<AutomationEffect> effects, {
    required String columnId,
    required String cardId,
  }) async {
    if (effects.isEmpty || _applyingAutomation || board == null) return;
    _applyingAutomation = true;
    try {
      for (final effect in effects) {
        final card = findCardById(cardId);
        final currentColumnId = findColumnIdForCard(cardId);
        if (card == null || currentColumnId == null) return;

        if (effect.moveToDone) {
          final done = _findDoneColumn(board!);
          if (done != null && done.id != currentColumnId) {
            await moveCard(
              cardId: cardId,
              fromColumnId: currentColumnId,
              toColumnId: done.id,
              toDisplayIndex: done.cards.length,
              completed: true,
              completedAt: DateTime.now().millisecondsSinceEpoch,
            );
          } else {
            await updateCardFull(
              currentColumnId,
              cardId,
              completed: true,
            );
          }
          continue;
        }

        var nextLabels = card.labels;
        if (effect.addLabelKey != null &&
            !nextLabels.contains(effect.addLabelKey)) {
          nextLabels = [...nextLabels, effect.addLabelKey!];
        }
        await updateCardFull(
          currentColumnId,
          cardId,
          completed: effect.completed,
          priority: effect.priority,
          labels: effect.addLabelKey == null ? null : nextLabels,
          clearReminder: effect.clearReminder,
        );
      }
    } finally {
      _applyingAutomation = false;
    }
  }

  /// 扫描并执行「已逾期」自动化。
  Future<void> runOverdueAutomations() async {
    if (board == null) return;
    final now = DateTime.now();
    for (final column in [...board!.columns]) {
      for (final card in [...column.cards]) {
        final effects = _BoardControllerBase._automationEngine.effectsForOverdue(
          rules: projectSettings.automationRules,
          card: card,
          now: now,
        );
        if (effects.isEmpty) continue;
        await _runAutomations(
          effects,
          columnId: column.id,
          cardId: card.id,
        );
      }
    }
  }
  Future<String?> toggleCardCompleted(String columnId, String cardId) async {
    return _withBoardMutation(() async {
      if (board == null) return null;
      final current = board!;
      KanbanCard? target;
      for (final col in current.columns) {
        for (final card in col.cards) {
          if (col.id == columnId && card.id == cardId) {
            target = card;
            break;
          }
        }
      }
      if (target == null) return null;

      final nextCompleted = !target.completed;
      if (nextCompleted &&
          hasIncompleteVerificationFeedback(target.verificationFeedback)) {
        return incompleteVerificationFeedbackBlocksProgressMessage;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final doneColumn = _findDoneColumn(current);

      if (nextCompleted && doneColumn != null && doneColumn.id != columnId) {
        final moveError = await moveCard(
          cardId: cardId,
          fromColumnId: columnId,
          toColumnId: doneColumn.id,
          toDisplayIndex: doneColumn.cards.length,
          completed: true,
          completedAt: now,
        );
        if (moveError != null) return moveError;
        await _afterCompletionChanged(
          target,
          sourceColumnId: columnId,
          completed: true,
        );
        return null;
      }

      if (!nextCompleted && doneColumn?.id == columnId) {
        final todoColumn = current.columns.cast<KanbanColumn?>().firstWhere(
              (col) => col!.id == 'todo',
              orElse: () =>
                  current.columns.isNotEmpty ? current.columns.first : null,
            );
        if (todoColumn != null && todoColumn.id != columnId) {
          final moveError = await moveCard(
            cardId: cardId,
            fromColumnId: columnId,
            toColumnId: todoColumn.id,
            toDisplayIndex: todoColumn.cards.length,
            completed: false,
            completedAt: null,
          );
          if (moveError != null) return moveError;
          await _afterCompletionChanged(
            target,
            sourceColumnId: columnId,
            completed: false,
          );
          return null;
        }
      }

      final updateError =
          await updateCardFull(columnId, cardId, completed: nextCompleted);
      if (updateError != null) return updateError;
      await _afterCompletionChanged(
        target,
        sourceColumnId: columnId,
        completed: nextCompleted,
      );
      return null;
    });
  }

  Future<void> _afterCompletionChanged(
    KanbanCard card, {
    required String sourceColumnId,
    required bool completed,
  }) async {
    await _reminderScheduler.cancel(card.id);
    if (completed) {
      final next = _BoardControllerBase._recurrenceService.createNextOccurrence(card);
      if (next != null &&
          board != null &&
          !board!.columns.any(
            (column) => column.cards.any((item) => item.id == next.id),
          )) {
        final columns = board!.columns.map((column) {
          if (column.id != sourceColumnId) return column;
          return column.copyWith(
            cards: [
              ...column.cards,
              next.copyWith(order: column.cards.length),
            ],
          );
        }).toList();
        await _persistAndSync(_bump(board!.copyWith(columns: columns)));
        if (next.reminderAt != null && activeProjectId != null) {
          await _scheduleCardReminder(
            projectId: activeProjectId!,
            columnId: sourceColumnId,
            card: next,
          );
        }
      }
    }
    await _recordActivity(
      entityId: card.id,
      entityTitle: card.title,
      action: completed ? ActivityAction.completed : ActivityAction.reopened,
    );
  }

  Future<String?> deleteCard(String columnId, String cardId) async {
    return _withBoardMutation(() async {
      if (board == null || activeProjectId == null) return null;

      KanbanCard? target;
      KanbanColumn? sourceColumn;
      for (final col in board!.columns) {
        if (col.id != columnId) continue;
        sourceColumn = col;
        for (final card in col.cards) {
          if (card.id == cardId) {
            target = card;
            break;
          }
        }
      }
      if (target == null || sourceColumn == null) return null;

      final now = DateTime.now().millisecondsSinceEpoch;
      final trashId = const Uuid().v4();
      await _addToActiveProjectTrash(
        TrashItem.forCard(
          trashId: trashId,
          deletedAt: now,
          projectId: activeProjectId!,
          projectTitle: board!.title,
          columnId: columnId,
          columnTitle: sourceColumn.title,
          card: target,
        ),
      );

      final columns = board!.columns.map((col) {
        if (col.id != columnId) return col;
        final cards = col.cards.where((c) => c.id != cardId).toList();
        return col.copyWith(cards: cards);
      }).toList();
      await _persistAndSync(_bump(board!.copyWith(columns: columns)));
      await _reminderScheduler.cancel(cardId);
      var currentTrashId = trashId;
      _pushUndo(
        '删除「${target.title}」',
        () async {
          final error = await restoreTrashItem(currentTrashId);
          if (error != null) throw StateError(error);
        },
        redo: () async {
          final id = await deleteCard(columnId, cardId);
          if (id != null) currentTrashId = id;
        },
      );
      await _recordActivity(
        entityId: cardId,
        entityTitle: target.title,
        action: ActivityAction.deleted,
      );
      return trashId;
    });
  }
}

