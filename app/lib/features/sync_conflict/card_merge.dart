import '../../models/kanban_models.dart';

/// 带列归属的卡片
class PlacedCard {
  const PlacedCard({
    required this.card,
    required this.columnId,
  });

  final KanbanCard card;
  final String columnId;
}

/// 卡片字段级三路合并结果
class CardMergeResult {
  const CardMergeResult({
    required this.placed,
    this.deleted = false,
  });

  final PlacedCard? placed;
  final bool deleted;
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _checklistEq(List<ChecklistItem> a, List<ChecklistItem> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id ||
        a[i].text != b[i].text ||
        a[i].completed != b[i].completed) {
      return false;
    }
  }
  return true;
}

bool _attachmentsEq(List<CardAttachment> a, List<CardAttachment> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id ||
        a[i].fileName != b[i].fileName ||
        a[i].order != b[i].order) {
      return false;
    }
  }
  return true;
}

bool _linksEq(List<CardLink> a, List<CardLink> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id ||
        a[i].url != b[i].url ||
        a[i].title != b[i].title ||
        a[i].order != b[i].order) {
      return false;
    }
  }
  return true;
}

bool cardsContentEqual(KanbanCard a, KanbanCard b) {
  return a.title == b.title &&
      a.description == b.description &&
      a.order == b.order &&
      a.completed == b.completed &&
      a.completedAt == b.completedAt &&
      a.dueDate == b.dueDate &&
      a.reminderAt == b.reminderAt &&
      a.recurrence == b.recurrence &&
      a.recurrenceSeriesId == b.recurrenceSeriesId &&
      a.priority == b.priority &&
      a.colorValue == b.colorValue &&
      _listEq(a.labels, b.labels) &&
      _checklistEq(a.checklist, b.checklist) &&
      _checklistEq(a.verificationFeedback, b.verificationFeedback) &&
      _attachmentsEq(a.attachments, b.attachments) &&
      _linksEq(a.links, b.links) &&
      _listEq(a.blockedByIds, b.blockedByIds) &&
      _listEq(a.relatedIds, b.relatedIds);
}

KanbanCard stripConflict(KanbanCard card) {
  return card.copyWith(
    clearConflict: true,
  );
}

KanbanCard _withConflict({
  required KanbanCard primary,
  required String primaryColumnId,
  required KanbanCard other,
  required String otherColumnId,
  bool otherDeleted = false,
}) {
  final side = stripConflict(other).copyWith(
    conflictDeleted: otherDeleted,
  );
  // note: 保留已有未解决冲突时，若 primary 已有 conflictSide 且与 other 不同，优先保留已有
  final existing = primary.conflictSide;
  final conflictSide = existing != null && !otherDeleted ? existing : side;
  return stripConflict(primary).copyWith(
    conflictSide: conflictSide,
    conflictColumnId: otherDeleted ? null : otherColumnId,
    conflictDeleted: otherDeleted,
  );
}

/// 无 base 时的两路卡片合并
CardMergeResult mergeCardTwoWay({
  required PlacedCard? local,
  required PlacedCard? remote,
}) {
  if (local == null && remote == null) {
    return const CardMergeResult(placed: null, deleted: true);
  }
  if (local == null) return CardMergeResult(placed: remote);
  if (remote == null) return CardMergeResult(placed: local);

  final localCard = local.card;
  final remoteCard = remote.card;

  // note: 已有未解决冲突：保留主内容较新者，并保留 conflictSide
  if (localCard.hasConflict || remoteCard.hasConflict) {
    final primary =
        localCard.updatedAt >= remoteCard.updatedAt ? local : remote;
    final other = identical(primary, local) ? remote : local;
    final preserved = primary.card.hasConflict
        ? primary.card
        : _withConflict(
            primary: primary.card,
            primaryColumnId: primary.columnId,
            other: other.card.conflictSide ?? other.card,
            otherColumnId: other.card.conflictColumnId ?? other.columnId,
            otherDeleted: other.card.conflictDeleted,
          );
    return CardMergeResult(
      placed: PlacedCard(card: preserved, columnId: primary.columnId),
    );
  }

  if (cardsContentEqual(localCard, remoteCard) &&
      local.columnId == remote.columnId) {
    final newer =
        localCard.updatedAt >= remoteCard.updatedAt ? localCard : remoteCard;
    return CardMergeResult(
      placed: PlacedCard(card: newer, columnId: local.columnId),
    );
  }

  final fieldConflict = _hasOverlappingFieldConflict(localCard, remoteCard) ||
      local.columnId != remote.columnId;

  if (!fieldConflict) {
    final merged = _mergeFieldsAuto(localCard, remoteCard);
    final col = localCard.updatedAt >= remoteCard.updatedAt
        ? local.columnId
        : remote.columnId;
    // note: 不同字段自动合时，列归属取 updatedAt 较新侧
    return CardMergeResult(
      placed: PlacedCard(card: merged, columnId: col),
    );
  }

  final localWins = localCard.updatedAt >= remoteCard.updatedAt;
  final primary = localWins ? local : remote;
  final other = localWins ? remote : local;
  return CardMergeResult(
    placed: PlacedCard(
      card: _withConflict(
        primary: primary.card,
        primaryColumnId: primary.columnId,
        other: other.card,
        otherColumnId: other.columnId,
      ),
      columnId: primary.columnId,
    ),
  );
}

bool _hasOverlappingFieldConflict(KanbanCard local, KanbanCard remote) {
  // note: 无 base 时，任一字段两边不同且双方都相对「空默认」有意义改动，视为同字段冲突
  // 简化：只要同名字段值不同就视为冲突（两路无法证明非重叠）
  return local.title != remote.title ||
      local.description != remote.description ||
      local.completed != remote.completed ||
      local.completedAt != remote.completedAt ||
      local.dueDate != remote.dueDate ||
      local.reminderAt != remote.reminderAt ||
      local.recurrence != remote.recurrence ||
      local.recurrenceSeriesId != remote.recurrenceSeriesId ||
      local.priority != remote.priority ||
      local.colorValue != remote.colorValue ||
      !_listEq(local.labels, remote.labels) ||
      !_checklistEq(local.checklist, remote.checklist) ||
      !_checklistEq(local.verificationFeedback, remote.verificationFeedback) ||
      !_attachmentsEq(local.attachments, remote.attachments) ||
      !_linksEq(local.links, remote.links) ||
      !_listEq(local.blockedByIds, remote.blockedByIds) ||
      !_listEq(local.relatedIds, remote.relatedIds);
}

KanbanCard _mergeFieldsAuto(KanbanCard local, KanbanCard remote) {
  // note: 两路且判定无同字段冲突时，实际上内容应已相等；保底取较新
  return local.updatedAt >= remote.updatedAt ? local : remote;
}

bool _fieldConflict<T>({
  required T base,
  required T local,
  required T remote,
  required bool Function(T a, T b) eq,
}) {
  final localChanged = !eq(local, base);
  final remoteChanged = !eq(remote, base);
  return localChanged && remoteChanged && !eq(local, remote);
}

/// 三路卡片合并（local / base / remote）
CardMergeResult mergeCardThreeWay({
  required PlacedCard? local,
  required PlacedCard? base,
  required PlacedCard? remote,
}) {
  if (base == null) {
    return mergeCardTwoWay(local: local, remote: remote);
  }

  // 双侧删除
  if (local == null && remote == null) {
    return const CardMergeResult(placed: null, deleted: true);
  }

  // 仅远端保留（本地删）
  if (local == null && remote != null) {
    final remoteChanged = !cardsContentEqual(remote.card, base.card) ||
        remote.columnId != base.columnId;
    if (remoteChanged) {
      // 删 vs 改：主侧保留仍存在的远端，冲突标记删除意图
      return CardMergeResult(
        placed: PlacedCard(
          card: stripConflict(remote.card).copyWith(
            conflictSide: stripConflict(base.card),
            conflictDeleted: true,
          ),
          columnId: remote.columnId,
        ),
      );
    }
    // 本地删且远端未改 → 接受删除
    return const CardMergeResult(placed: null, deleted: true);
  }

  // 仅本地保留（远端删）
  if (local != null && remote == null) {
    final localChanged = !cardsContentEqual(local.card, base.card) ||
        local.columnId != base.columnId;
    if (localChanged) {
      return CardMergeResult(
        placed: PlacedCard(
          card: stripConflict(local.card).copyWith(
            conflictSide: stripConflict(base.card),
            conflictDeleted: true,
          ),
          columnId: local.columnId,
        ),
      );
    }
    return const CardMergeResult(placed: null, deleted: true);
  }

  final loc = local!;
  final rem = remote!;

  // 保留已有冲突
  if (loc.card.hasConflict || rem.card.hasConflict) {
    return mergeCardTwoWay(local: loc, remote: rem);
  }

  final titleConflict = _fieldConflict(
    base: base.card.title,
    local: loc.card.title,
    remote: rem.card.title,
    eq: (a, b) => a == b,
  );
  final descConflict = _fieldConflict(
    base: base.card.description,
    local: loc.card.description,
    remote: rem.card.description,
    eq: (a, b) => a == b,
  );
  final completedConflict = _fieldConflict(
    base: base.card.completed,
    local: loc.card.completed,
    remote: rem.card.completed,
    eq: (a, b) => a == b,
  );
  final completedAtConflict = _fieldConflict(
    base: base.card.completedAt,
    local: loc.card.completedAt,
    remote: rem.card.completedAt,
    eq: (a, b) => a == b,
  );
  final dueConflict = _fieldConflict(
    base: base.card.dueDate,
    local: loc.card.dueDate,
    remote: rem.card.dueDate,
    eq: (a, b) => a == b,
  );
  final reminderConflict = _fieldConflict(
    base: base.card.reminderAt,
    local: loc.card.reminderAt,
    remote: rem.card.reminderAt,
    eq: (a, b) => a == b,
  );
  final recurrenceConflict = _fieldConflict(
    base: base.card.recurrence,
    local: loc.card.recurrence,
    remote: rem.card.recurrence,
    eq: (a, b) => a == b,
  );
  final recurrenceSeriesConflict = _fieldConflict(
    base: base.card.recurrenceSeriesId,
    local: loc.card.recurrenceSeriesId,
    remote: rem.card.recurrenceSeriesId,
    eq: (a, b) => a == b,
  );
  final priorityConflict = _fieldConflict(
    base: base.card.priority,
    local: loc.card.priority,
    remote: rem.card.priority,
    eq: (a, b) => a == b,
  );
  final colorConflict = _fieldConflict(
    base: base.card.colorValue,
    local: loc.card.colorValue,
    remote: rem.card.colorValue,
    eq: (a, b) => a == b,
  );
  final labelsConflict = _fieldConflict(
    base: base.card.labels,
    local: loc.card.labels,
    remote: rem.card.labels,
    eq: _listEq,
  );
  final checklistConflict = _fieldConflict(
    base: base.card.checklist,
    local: loc.card.checklist,
    remote: rem.card.checklist,
    eq: _checklistEq,
  );
  final verificationFeedbackConflict = _fieldConflict(
    base: base.card.verificationFeedback,
    local: loc.card.verificationFeedback,
    remote: rem.card.verificationFeedback,
    eq: _checklistEq,
  );
  final attachmentsConflict = _fieldConflict(
    base: base.card.attachments,
    local: loc.card.attachments,
    remote: rem.card.attachments,
    eq: _attachmentsEq,
  );
  final linksConflict = _fieldConflict(
    base: base.card.links,
    local: loc.card.links,
    remote: rem.card.links,
    eq: _linksEq,
  );
  final blockedByConflict = _fieldConflict(
    base: base.card.blockedByIds,
    local: loc.card.blockedByIds,
    remote: rem.card.blockedByIds,
    eq: _listEq,
  );
  final relatedConflict = _fieldConflict(
    base: base.card.relatedIds,
    local: loc.card.relatedIds,
    remote: rem.card.relatedIds,
    eq: _listEq,
  );
  final columnConflict = _fieldConflict(
    base: base.columnId,
    local: loc.columnId,
    remote: rem.columnId,
    eq: (a, b) => a == b,
  );

  final anyConflict = titleConflict ||
      descConflict ||
      completedConflict ||
      completedAtConflict ||
      dueConflict ||
      reminderConflict ||
      recurrenceConflict ||
      recurrenceSeriesConflict ||
      priorityConflict ||
      colorConflict ||
      labelsConflict ||
      checklistConflict ||
      verificationFeedbackConflict ||
      attachmentsConflict ||
      linksConflict ||
      blockedByConflict ||
      relatedConflict ||
      columnConflict;

  if (anyConflict) {
    final localWins = loc.card.updatedAt >= rem.card.updatedAt;
    final primary = localWins ? loc : rem;
    final other = localWins ? rem : loc;
    return CardMergeResult(
      placed: PlacedCard(
        card: _withConflict(
          primary: primary.card,
          primaryColumnId: primary.columnId,
          other: other.card,
          otherColumnId: other.columnId,
        ),
        columnId: primary.columnId,
      ),
    );
  }

  // 字段级自动合
  final mergedTitle = _threeWayValue(
    base: base.card.title,
    local: loc.card.title,
    remote: rem.card.title,
  );
  final mergedDesc = _threeWayValue(
    base: base.card.description,
    local: loc.card.description,
    remote: rem.card.description,
  );
  final mergedCompleted = _threeWayValue(
    base: base.card.completed,
    local: loc.card.completed,
    remote: rem.card.completed,
  );
  final mergedCompletedAt = _threeWayValue(
    base: base.card.completedAt,
    local: loc.card.completedAt,
    remote: rem.card.completedAt,
  );
  final mergedDue = _threeWayValue(
    base: base.card.dueDate,
    local: loc.card.dueDate,
    remote: rem.card.dueDate,
  );
  final mergedReminder = _threeWayValue(
    base: base.card.reminderAt,
    local: loc.card.reminderAt,
    remote: rem.card.reminderAt,
  );
  final mergedRecurrence = _threeWayValue(
    base: base.card.recurrence,
    local: loc.card.recurrence,
    remote: rem.card.recurrence,
  );
  final mergedRecurrenceSeries = _threeWayValue(
    base: base.card.recurrenceSeriesId,
    local: loc.card.recurrenceSeriesId,
    remote: rem.card.recurrenceSeriesId,
  );
  final mergedPriority = _threeWayValue(
    base: base.card.priority,
    local: loc.card.priority,
    remote: rem.card.priority,
  );
  final mergedColor = _threeWayValue(
    base: base.card.colorValue,
    local: loc.card.colorValue,
    remote: rem.card.colorValue,
  );
  final mergedLabels = _threeWayValue(
    base: base.card.labels,
    local: loc.card.labels,
    remote: rem.card.labels,
    eq: _listEq,
  );
  final mergedChecklist = _threeWayValue(
    base: base.card.checklist,
    local: loc.card.checklist,
    remote: rem.card.checklist,
    eq: _checklistEq,
  );
  final mergedVerificationFeedback = _threeWayValue(
    base: base.card.verificationFeedback,
    local: loc.card.verificationFeedback,
    remote: rem.card.verificationFeedback,
    eq: _checklistEq,
  );
  final mergedAttachments = _threeWayValue(
    base: base.card.attachments,
    local: loc.card.attachments,
    remote: rem.card.attachments,
    eq: _attachmentsEq,
  );
  final mergedLinks = _threeWayValue(
    base: base.card.links,
    local: loc.card.links,
    remote: rem.card.links,
    eq: _linksEq,
  );
  final mergedBlockedBy = _threeWayValue(
    base: base.card.blockedByIds,
    local: loc.card.blockedByIds,
    remote: rem.card.blockedByIds,
    eq: _listEq,
  );
  final mergedRelated = _threeWayValue(
    base: base.card.relatedIds,
    local: loc.card.relatedIds,
    remote: rem.card.relatedIds,
    eq: _listEq,
  );
  final columnId = _threeWayValue(
    base: base.columnId,
    local: loc.columnId,
    remote: rem.columnId,
  );

  final merged = KanbanCard(
    id: loc.card.id,
    title: mergedTitle,
    description: mergedDesc,
    order: loc.card.updatedAt >= rem.card.updatedAt
        ? loc.card.order
        : rem.card.order,
    createdAt: loc.card.createdAt,
    updatedAt: loc.card.updatedAt >= rem.card.updatedAt
        ? loc.card.updatedAt
        : rem.card.updatedAt,
    completed: mergedCompleted,
    completedAt: mergedCompletedAt,
    dueDate: mergedDue,
    reminderAt: mergedReminder,
    recurrence: mergedRecurrence,
    recurrenceSeriesId: mergedRecurrenceSeries,
    priority: mergedPriority,
    labels: mergedLabels,
    checklist: mergedChecklist,
    verificationFeedback: mergedVerificationFeedback,
    attachments: mergedAttachments,
    links: mergedLinks,
    blockedByIds: mergedBlockedBy,
    relatedIds: mergedRelated,
    colorValue: mergedColor,
  );

  return CardMergeResult(
    placed: PlacedCard(card: merged, columnId: columnId),
  );
}

T _threeWayValue<T>({
  required T base,
  required T local,
  required T remote,
  bool Function(T a, T b)? eq,
}) {
  final equal = eq ?? ((T a, T b) => a == b);
  final localChanged = !equal(local, base);
  final remoteChanged = !equal(remote, base);
  if (localChanged) return local;
  if (remoteChanged) return remote;
  return base;
}

Map<String, PlacedCard> indexCards(KanbanBoard board) {
  final map = <String, PlacedCard>{};
  for (final col in board.columns) {
    for (final card in col.cards) {
      map[card.id] = PlacedCard(card: card, columnId: col.id);
    }
  }
  return map;
}
