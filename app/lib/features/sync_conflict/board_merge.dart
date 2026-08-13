import 'dart:convert';

import '../../models/kanban_models.dart';
import 'card_merge.dart';

extension KanbanBoardMerge on KanbanBoard {
  /// 两路合并（无 SyncBase 时）
  KanbanBoard mergeWith(KanbanBoard remote) =>
      mergeBoards(local: this, remote: remote);
}

/// 合并两块看板（无 base 时两路；有 base 时三路）
KanbanBoard mergeBoards({
  required KanbanBoard local,
  required KanbanBoard remote,
  KanbanBoard? base,
}) {
  // 两侧内容已一致时不要重建列/卡片，避免无意义的序列化差异触发整表回推。
  if (jsonEncode(local.toJson()) == jsonEncode(remote.toJson())) {
    return local;
  }
  final localCards = indexCards(local);
  final remoteCards = indexCards(remote);
  final baseCards = base == null ? <String, PlacedCard>{} : indexCards(base);

  final allCardIds = <String>{
    ...localCards.keys,
    ...remoteCards.keys,
    ...baseCards.keys,
  };

  final mergedPlacement = <String, PlacedCard>{};
  for (final id in allCardIds) {
    final result = mergeCardThreeWay(
      local: localCards[id],
      base: baseCards[id],
      remote: remoteCards[id],
    );
    if (result.deleted || result.placed == null) continue;
    mergedPlacement[id] = result.placed!;
  }

  // note: 列元数据第一期 LWW；列 id 并集
  final bool remoteWins;
  if (remote.revision > local.revision) {
    remoteWins = true;
  } else if (remote.revision < local.revision) {
    remoteWins = false;
  } else {
    remoteWins = remote.updatedAt >= local.updatedAt;
  }
  final winner = remoteWins ? remote : local;
  final loser = remoteWins ? local : remote;

  final winnerCols = {for (final c in winner.columns) c.id: c};
  final loserCols = {for (final c in loser.columns) c.id: c};
  final baseCols = {
    for (final c in base?.columns ?? const <KanbanColumn>[]) c.id: c,
  };

  final columnIds = <String>{
    ...winnerCols.keys,
    ...loserCols.keys,
    // note: 仅 base 有而两边都无的列视为已删，不并回
  };

  // 三路列删除：base 有、local/remote 都无 → 不保留
  if (base != null) {
    for (final id in baseCols.keys) {
      if (!winnerCols.containsKey(id) && !loserCols.containsKey(id)) {
        columnIds.remove(id);
      }
    }
    // 确保 local/remote 仍有的列都在
    columnIds.addAll(winnerCols.keys);
    columnIds.addAll(loserCols.keys);
  }

  String? conflictTitle;
  final localTitleChanged =
      base == null ? local.title != remote.title : local.title != base.title;
  final remoteTitleChanged =
      base == null ? remote.title != local.title : remote.title != base.title;
  if (base != null &&
      localTitleChanged &&
      remoteTitleChanged &&
      local.title != remote.title) {
    conflictTitle = remoteWins ? local.title : remote.title;
  } else if (base == null && local.title != remote.title) {
    conflictTitle = remoteWins ? local.title : remote.title;
  } else if (local.conflictTitle != null || remote.conflictTitle != null) {
    conflictTitle = winner.conflictTitle ?? loser.conflictTitle;
  }

  final title = base == null
      ? winner.title
      : (localTitleChanged && !remoteTitleChanged
          ? local.title
          : remoteTitleChanged && !localTitleChanged
              ? remote.title
              : winner.title);

  final mergedColumns = <KanbanColumn>[];
  for (final id in columnIds) {
    final primary = winnerCols[id];
    final secondary = loserCols[id];
    final template = primary ?? secondary!;
    final cards = mergedPlacement.values
        .where((e) => e.columnId == id)
        .map((e) => e.card)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    mergedColumns.add(
      template.copyWith(
        title: primary?.title ?? secondary!.title,
        order: primary?.order ?? secondary!.order,
        colorValue: primary?.colorValue ?? secondary?.colorValue,
        cards: cards,
      ),
    );
  }
  mergedColumns.sort((a, b) => a.order.compareTo(b.order));

  return winner.copyWith(
    title: title,
    conflictTitle: conflictTitle,
    clearConflictTitle: conflictTitle == null,
    updatedAt: local.updatedAt > remote.updatedAt
        ? local.updatedAt
        : remote.updatedAt,
    revision: local.revision > remote.revision
        ? local.revision
        : remote.revision,
    columns: mergedColumns,
  );
}
