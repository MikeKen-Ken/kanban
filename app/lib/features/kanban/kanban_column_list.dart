import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../common/app_snack_bar.dart';
import '../../models/kanban_models.dart';
import 'board_horizontal_scroll.dart';
import 'card_complete_motion.dart';
import 'column_card_preferences.dart';
import 'kanban_card_tile.dart';
import 'kanban_motion.dart';

/// 整列可拖放：列表任意位置均可接收卡片，按指针 Y 坐标计算插入位置。
class KanbanColumnList extends StatefulWidget {
  const KanbanColumnList({
    super.key,
    required this.columnId,
    required this.cards,
    required this.allColumns,
    this.searchQuery = '',
    this.sortMode = CardSortMode.updatedAt,
    this.pinnedCardIds = const [],
  });

  final String columnId;
  final List<KanbanCard> cards;
  final List<KanbanColumn> allColumns;
  final String searchQuery;
  final CardSortMode sortMode;
  final List<String> pinnedCardIds;

  @override
  State<KanbanColumnList> createState() => _KanbanColumnListState();
}

class _KanbanColumnListState extends State<KanbanColumnList> {
  final Map<String, GlobalKey> _cardKeys = {};
  final ScrollController _scrollController = ScrollController();
  late List<TrackedKanbanCard> _tracked;
  int? _hoverInsertIndex;

  @override
  void initState() {
    super.initState();
    _tracked = [for (final card in widget.cards) TrackedKanbanCard(card: card)];
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    tryClaimVerticalWheelForColumnScroll(
      event: event,
      controller: _scrollController,
    );
  }

  bool get _allowWithinColumnReorder => widget.sortMode == CardSortMode.custom;

  int get _pinnedCount =>
      pinnedCardCount(widget.pinnedCardIds, widget.cards);

  @override
  void didUpdateWidget(covariant KanbanColumnList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tracked = reconcileTrackedKanbanCards(
      previous: _tracked,
      next: widget.cards,
    );
    _pruneCardKeys();
  }

  void _pruneCardKeys() {
    final ids = {for (final item in _tracked) item.card.id};
    _cardKeys.removeWhere((id, _) => !ids.contains(id));
  }

  GlobalKey _keyFor(String cardId) {
    return _cardKeys.putIfAbsent(cardId, GlobalKey.new);
  }

  int _insertIndexForGlobalDy(double globalDy) {
    if (widget.cards.isEmpty) return 0;

    var modelIndex = 0;
    for (final item in _tracked) {
      if (item.leaving) continue;
      final context = _keyFor(item.card.id).currentContext;
      if (context == null) {
        modelIndex++;
        continue;
      }
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        modelIndex++;
        continue;
      }

      final top = renderObject.localToGlobal(Offset.zero).dy;
      final mid = top + renderObject.size.height / 2;
      if (globalDy < mid) return modelIndex;
      modelIndex++;
    }
    return widget.cards.length;
  }

  int _clampInsertIndex(KanbanCard dragged, int insertIndex) {
    if (!_allowWithinColumnReorder) {
      return widget.cards.length;
    }

    final movingPinned = widget.pinnedCardIds.contains(dragged.id);
    if (movingPinned) {
      return insertIndex.clamp(0, _pinnedCount);
    }
    return insertIndex.clamp(_pinnedCount, widget.cards.length);
  }

  Future<void> _acceptDrop(KanbanCard dragged, int insertIndex) async {
    final controller = context.read<BoardController>();
    final fromColumn = _findColumnId(controller, dragged.id);
    if (fromColumn == null) return;

    if (fromColumn == widget.columnId && !_allowWithinColumnReorder) {
      return;
    }

    final error = await controller.moveCard(
      cardId: dragged.id,
      fromColumnId: fromColumn,
      toColumnId: widget.columnId,
      toDisplayIndex: _clampInsertIndex(dragged, insertIndex),
    );
    if (error != null && mounted) {
      showAppSnackBar(context, message: error);
    }
  }

  void _onCardLeft(String cardId) {
    if (!mounted) return;
    setState(() {
      _tracked = [
        for (final item in _tracked)
          if (!(item.card.id == cardId && item.leaving)) item,
      ];
      _pruneCardKeys();
    });
  }

  @override
  Widget build(BuildContext context) {
    _pruneCardKeys();
    final colorScheme = Theme.of(context).colorScheme;

    return DragTarget<KanbanCard>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (details) {
        final rawIndex = _insertIndexForGlobalDy(details.offset.dy);
        final index = _clampInsertIndex(details.data, rawIndex);
        if (index != _hoverInsertIndex) {
          setState(() => _hoverInsertIndex = index);
        }
      },
      onLeave: (_) {
        if (_hoverInsertIndex != null) {
          setState(() => _hoverInsertIndex = null);
        }
      },
      onAcceptWithDetails: (details) {
        final rawIndex = _insertIndexForGlobalDy(details.offset.dy);
        setState(() => _hoverInsertIndex = null);
        _acceptDrop(details.data, rawIndex);
      },
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        final showIndicator =
            active && _hoverInsertIndex != null && _allowWithinColumnReorder;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: active
                ? colorScheme.primary.withValues(alpha: 0.06)
                : null,
            border: active
                ? Border.all(color: colorScheme.primary.withValues(alpha: 0.45))
                : null,
          ),
          child: _tracked.isEmpty
              ? Center(
                  child: Text(
                    '暂无卡片',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                  ),
                )
              : Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerSignal: _onPointerSignal,
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    children: [
                    if (_pinnedCount > 0 && _allowWithinColumnReorder)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 4),
                        child: Text(
                          '置顶',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                              ),
                        ),
                      ),
                    ..._cardChildren(showIndicator, colorScheme),
                    if (showIndicator &&
                        _hoverInsertIndex == widget.cards.length)
                      _InsertionIndicator(colorScheme: colorScheme),
                    const SizedBox(height: 8),
                  ],
                  ),
                ),
        );
      },
    );
  }

  List<Widget> _cardChildren(bool showIndicator, ColorScheme colorScheme) {
    final children = <Widget>[];
    var displayIndex = 0;
    for (final item in _tracked) {
      if (!item.leaving) {
        if (showIndicator && _hoverInsertIndex == displayIndex) {
          children.add(_InsertionIndicator(colorScheme: colorScheme));
        }
        if (_allowWithinColumnReorder &&
            displayIndex == _pinnedCount &&
            _pinnedCount > 0 &&
            displayIndex < widget.cards.length) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 4, top: 2, left: 4),
              child: Text(
                '其余卡片',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          );
        }
      }
      children.add(
        _KanbanEnterLeave(
          key: _keyFor(item.card.id),
          leaving: item.leaving,
          animateEnter: item.animateEnter,
          onLeft: () => _onCardLeft(item.card.id),
          child: CardLayoutAnchor.card(
            cardId: item.card.id,
            child: CardFlightHidden(
              cardId: item.card.id,
              child: KanbanCardTile(
                columnId: widget.columnId,
                card: item.card,
                allColumns: widget.allColumns,
                searchQuery: widget.searchQuery,
                isPinned: widget.pinnedCardIds.contains(item.card.id),
                onDragStarted: () =>
                    setState(() => _hoverInsertIndex = null),
              ),
            ),
          ),
        ),
      );
      if (!item.leaving) displayIndex++;
    }
    return children;
  }

  String? _findColumnId(BoardController controller, String cardId) {
    final board = controller.board;
    if (board == null) return null;
    for (final col in board.columns) {
      if (col.cards.any((c) => c.id == cardId)) return col.id;
    }
    return null;
  }
}

class _KanbanEnterLeave extends StatefulWidget {
  const _KanbanEnterLeave({
    super.key,
    required this.leaving,
    required this.animateEnter,
    required this.onLeft,
    required this.child,
  });

  final bool leaving;
  final bool animateEnter;
  final VoidCallback onLeft;
  final Widget child;

  @override
  State<_KanbanEnterLeave> createState() => _KanbanEnterLeaveState();
}

class _KanbanEnterLeaveState extends State<_KanbanEnterLeave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _factor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kKanbanListMotionDuration,
    );
    _factor = CurvedAnimation(
      parent: _controller,
      curve: kKanbanMotionCurve,
      reverseCurve: kKanbanMotionCurve,
    );
    if (widget.leaving) {
      _controller.value = 1;
      _playLeave();
    } else if (widget.animateEnter) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _KanbanEnterLeave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leaving && !oldWidget.leaving) {
      _playLeave();
    } else if (!widget.leaving && oldWidget.leaving) {
      _controller.forward();
    }
  }

  Future<void> _playLeave() async {
    await _controller.reverse();
    if (mounted && widget.leaving) widget.onLeft();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _factor,
      child: SizeTransition(
        sizeFactor: _factor,
        alignment: Alignment.topCenter,
        child: widget.child,
      ),
    );
  }
}

class _InsertionIndicator extends StatelessWidget {
  const _InsertionIndicator({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
