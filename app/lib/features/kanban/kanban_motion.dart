import 'package:flutter/material.dart';

import '../../models/kanban_models.dart';

/// 看板列宽、卡片进出的统一节奏。
const kKanbanListMotionDuration = Duration(milliseconds: 240);
const kKanbanColumnWidthDuration = kKanbanListMotionDuration;
const kKanbanMotionCurve = Curves.easeOutCubic;

/// 单次增删超过该数量时不再播放进出动画（同步全量刷新等）。
const kKanbanListAnimateThreshold = 6;

/// 列内卡片列表的过渡条目：保留正在离场的卡片，直到退出动画结束。
class TrackedKanbanCard {
  const TrackedKanbanCard({
    required this.card,
    this.leaving = false,
    this.animateEnter = false,
    this.heldForFlight = false,
  });

  final KanbanCard card;
  final bool leaving;
  final bool animateEnter;

  /// 完成飞行期间留在源列的占位，避免列表一边飞一边收高度。
  final bool heldForFlight;
}

/// 把上一帧展示列表与最新数据对齐，供进出动画使用。
List<TrackedKanbanCard> reconcileTrackedKanbanCards({
  required List<TrackedKanbanCard> previous,
  required List<KanbanCard> next,
  int animateThreshold = kKanbanListAnimateThreshold,
  String? holdCardId,
}) {
  final nextById = {for (final card in next) card.id: card};
  final previousActiveIds = [
    for (final item in previous)
      if (!item.leaving) item.card.id,
  ];
  final removedCount = previousActiveIds
      .where((id) => !nextById.containsKey(id) && id != holdCardId)
      .length;
  final insertedCount = next
      .where(
        (card) => !previousActiveIds.contains(card.id) && card.id != holdCardId,
      )
      .length;
  final animate = previous.isNotEmpty &&
      next.isNotEmpty &&
      removedCount + insertedCount <= animateThreshold;

  if (!animate) {
    final result = [
      for (final card in next) TrackedKanbanCard(card: card),
    ];
    if (holdCardId != null && !nextById.containsKey(holdCardId)) {
      final held = _heldFlightPlaceholder(previous, holdCardId);
      if (held.isNotEmpty) {
        final oldIndex =
            previous.indexWhere((item) => item.card.id == holdCardId);
        final index =
            (oldIndex < 0 ? result.length : oldIndex).clamp(0, result.length);
        result.insert(index, held.first);
      }
    }
    return result;
  }

  final oldIndex = <String, int>{
    for (var i = 0; i < previous.length; i++) previous[i].card.id: i,
  };
  final insertedIds = {
    for (final card in next)
      if (!previousActiveIds.contains(card.id)) card.id,
  };

  final result = <TrackedKanbanCard>[
    for (final card in next)
      TrackedKanbanCard(
        card: card,
        animateEnter: insertedIds.contains(card.id) && card.id != holdCardId,
      ),
  ];

  final leaving = [
    for (final item in previous)
      if (!nextById.containsKey(item.card.id) &&
          item.card.id != holdCardId &&
          !item.heldForFlight)
        TrackedKanbanCard(card: item.card, leaving: true),
  ]..sort(
      (a, b) => (oldIndex[a.card.id] ?? 0).compareTo(oldIndex[b.card.id] ?? 0),
    );

  for (final item in leaving) {
    final index =
        (oldIndex[item.card.id] ?? result.length).clamp(0, result.length);
    result.insert(index, item);
  }

  if (holdCardId != null && !nextById.containsKey(holdCardId)) {
    final held = _heldFlightPlaceholder(previous, holdCardId);
    if (held.isNotEmpty) {
      final index =
          (oldIndex[holdCardId] ?? result.length).clamp(0, result.length);
      result.insert(index, held.first);
    }
  }
  return result;
}

List<TrackedKanbanCard> _heldFlightPlaceholder(
  List<TrackedKanbanCard> previous,
  String holdCardId,
) {
  for (final item in previous) {
    if (item.card.id == holdCardId) {
      return [
        TrackedKanbanCard(card: item.card, heldForFlight: true),
      ];
    }
  }
  return const [];
}

/// 用 [SizedBox] 插值列宽，避免 [AnimatedContainer] 在横向列表里被拉满。
class AnimatedKanbanColumnWidth extends StatefulWidget {
  const AnimatedKanbanColumnWidth({
    super.key,
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  State<AnimatedKanbanColumnWidth> createState() =>
      _AnimatedKanbanColumnWidthState();
}

class _AnimatedKanbanColumnWidthState extends State<AnimatedKanbanColumnWidth>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _from = widget.width;
    _to = widget.width;
    _controller = AnimationController(
      vsync: this,
      duration: kKanbanColumnWidthDuration,
    )..value = 1;
  }

  @override
  void didUpdateWidget(covariant AnimatedKanbanColumnWidth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.width != _to) {
      final t = kKanbanMotionCurve.transform(_controller.value);
      _from = _from + (_to - _from) * t;
      _to = widget.width;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = kKanbanMotionCurve.transform(_controller.value);
        return SizedBox(
          width: _from + (_to - _from) * t,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
