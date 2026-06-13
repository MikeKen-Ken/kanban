import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import 'column_card_preferences.dart';
import 'kanban_card_tile.dart';

/// 整列可拖放：列表任意位置均可接收卡片，按指针 Y 坐标计算插入位置。
class KanbanColumnList extends StatefulWidget {
  const KanbanColumnList({
    super.key,
    required this.columnId,
    required this.cards,
    required this.allColumns,
    this.searchQuery = '',
    this.sortMode = CardSortMode.custom,
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
  final List<GlobalKey> _cardKeys = [];
  int? _hoverInsertIndex;

  bool get _allowWithinColumnReorder => widget.sortMode == CardSortMode.custom;

  int get _pinnedCount =>
      pinnedCardCount(widget.pinnedCardIds, widget.cards);

  @override
  void didUpdateWidget(covariant KanbanColumnList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCardKeys();
  }

  void _syncCardKeys() {
    while (_cardKeys.length < widget.cards.length) {
      _cardKeys.add(GlobalKey());
    }
    if (_cardKeys.length > widget.cards.length) {
      _cardKeys.removeRange(widget.cards.length, _cardKeys.length);
    }
  }

  int _insertIndexForGlobalDy(double globalDy) {
    if (widget.cards.isEmpty) return 0;

    for (var i = 0; i < _cardKeys.length; i++) {
      final context = _cardKeys[i].currentContext;
      if (context == null) continue;
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;

      final top = renderObject.localToGlobal(Offset.zero).dy;
      final mid = top + renderObject.size.height / 2;
      if (globalDy < mid) return i;
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

  void _acceptDrop(KanbanCard dragged, int insertIndex) {
    final controller = context.read<BoardController>();
    final fromColumn = _findColumnId(controller, dragged.id);
    if (fromColumn == null) return;

    if (fromColumn == widget.columnId && !_allowWithinColumnReorder) {
      return;
    }

    controller.moveCard(
      cardId: dragged.id,
      fromColumnId: fromColumn,
      toColumnId: widget.columnId,
      toDisplayIndex: _clampInsertIndex(dragged, insertIndex),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncCardKeys();
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
          child: widget.cards.isEmpty
              ? Center(
                  child: Text(
                    '暂无卡片',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                  ),
                )
              : ListView(
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
                    for (var i = 0; i < widget.cards.length; i++) ...[
                      if (showIndicator && _hoverInsertIndex == i)
                        _InsertionIndicator(colorScheme: colorScheme),
                      if (_allowWithinColumnReorder &&
                          i == _pinnedCount &&
                          _pinnedCount > 0 &&
                          i < widget.cards.length)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4, top: 2, left: 4),
                          child: Text(
                            '其余卡片',
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                          ),
                        ),
                      KeyedSubtree(
                        key: _cardKeys[i],
                        child: KanbanCardTile(
                          columnId: widget.columnId,
                          card: widget.cards[i],
                          allColumns: widget.allColumns,
                          searchQuery: widget.searchQuery,
                          isPinned:
                              widget.pinnedCardIds.contains(widget.cards[i].id),
                          onDragStarted: () =>
                              setState(() => _hoverInsertIndex = null),
                        ),
                      ),
                    ],
                    if (showIndicator &&
                        _hoverInsertIndex == widget.cards.length)
                      _InsertionIndicator(colorScheme: colorScheme),
                    const SizedBox(height: 8),
                  ],
                ),
        );
      },
    );
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
