import '../../models/kanban_models.dart';
import 'kanban_labels.dart';

/// 列内卡片排序方式
enum CardSortMode {
  custom('自定义'),
  updatedAt('按时间'),
  name('按名称'),
  priority('按紧急程度'),
  dueDate('按到期时间'),
  createdAt('按添加时间');

  const CardSortMode(this.label);

  final String label;

  static CardSortMode fromName(String? name) {
    return CardSortMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => CardSortMode.custom,
    );
  }
}

/// 单列的卡片展示偏好（随项目同步）
class ColumnCardPreferences {
  const ColumnCardPreferences({
    this.sortMode = CardSortMode.custom,
    this.pinnedCardIds = const [],
  });

  final CardSortMode sortMode;
  final List<String> pinnedCardIds;

  ColumnCardPreferences copyWith({
    CardSortMode? sortMode,
    List<String>? pinnedCardIds,
  }) {
    return ColumnCardPreferences(
      sortMode: sortMode ?? this.sortMode,
      pinnedCardIds: pinnedCardIds ?? this.pinnedCardIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'sortMode': sortMode.name,
        'pinnedCardIds': pinnedCardIds,
      };

  factory ColumnCardPreferences.fromJson(Map<String, dynamic> json) {
    return ColumnCardPreferences(
      sortMode: CardSortMode.fromName(json['sortMode'] as String?),
      pinnedCardIds: (json['pinnedCardIds'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }
}

/// 置顶项始终在最前；非自定义模式下 `order` 仅保留手动顺序，切回自定义时恢复
List<KanbanCard> sortColumnCards(
  List<KanbanCard> cards, {
  required CardSortMode sortMode,
  required List<String> pinnedCardIds,
}) {
  if (cards.isEmpty) return const [];

  final byId = {for (final card in cards) card.id: card};
  final pinned = <KanbanCard>[
    for (final id in pinnedCardIds)
      if (byId.containsKey(id)) byId[id]!,
  ];
  final pinnedSet = pinned.map((card) => card.id).toSet();
  final unpinned = cards.where((card) => !pinnedSet.contains(card.id)).toList();

  switch (sortMode) {
    case CardSortMode.custom:
      unpinned.sort((a, b) => a.order.compareTo(b.order));
    case CardSortMode.name:
      unpinned.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    case CardSortMode.priority:
      unpinned.sort((a, b) {
        final byPriority = b.priority.sortWeight.compareTo(a.priority.sortWeight);
        if (byPriority != 0) return byPriority;
        return a.order.compareTo(b.order);
      });
    case CardSortMode.dueDate:
      unpinned.sort((a, b) {
        final ad = a.dueDate;
        final bd = b.dueDate;
        if (ad == null && bd == null) return a.order.compareTo(b.order);
        if (ad == null) return 1;
        if (bd == null) return -1;
        final byDue = ad.compareTo(bd);
        if (byDue != 0) return byDue;
        return a.order.compareTo(b.order);
      });
    case CardSortMode.createdAt:
      unpinned.sort((a, b) {
        final byCreated = b.createdAt.compareTo(a.createdAt);
        if (byCreated != 0) return byCreated;
        return a.order.compareTo(b.order);
      });
    case CardSortMode.updatedAt:
      unpinned.sort((a, b) {
        final byUpdated = b.updatedAt.compareTo(a.updatedAt);
        if (byUpdated != 0) return byUpdated;
        return a.order.compareTo(b.order);
      });
  }

  return [...pinned, ...unpinned];
}

int pinnedCardCount(List<String> pinnedCardIds, List<KanbanCard> cards) {
  final cardIds = cards.map((card) => card.id).toSet();
  return pinnedCardIds.where(cardIds.contains).length;
}
