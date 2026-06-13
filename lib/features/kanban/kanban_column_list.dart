import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import 'kanban_card_tile.dart';

/// 整列可拖放：列表任意位置均可接收卡片，按指针 Y 坐标计算插入位置。
class KanbanColumnList extends StatefulWidget {
  const KanbanColumnList({
    super.key,
    required this.columnId,
    required this.cards,
    required this.allColumns,
    this.searchQuery = '',
  });

  final String columnId;
  final List<KanbanCard> cards;
  final List<KanbanColumn> allColumns;
  final String searchQuery;

  @override
  State<KanbanColumnList> createState() => _KanbanColumnListState();
}

class _KanbanColumnListState extends State<KanbanColumnList> {
  final List<GlobalKey> _cardKeys = [];
  int? _hoverInsertIndex;

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

  void _acceptDrop(KanbanCard dragged, int insertIndex) {
    final controller = context.read<BoardController>();
    final fromColumn = _findColumnId(controller, dragged.id);
    if (fromColumn == null) return;

    controller.moveCard(
      cardId: dragged.id,
      fromColumnId: fromColumn,
      toColumnId: widget.columnId,
      toIndex: insertIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncCardKeys();
    final colorScheme = Theme.of(context).colorScheme;

    return DragTarget<KanbanCard>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (details) {
        final index = _insertIndexForGlobalDy(details.offset.dy);
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
        final index = _insertIndexForGlobalDy(details.offset.dy);
        setState(() => _hoverInsertIndex = null);
        _acceptDrop(details.data, index);
      },
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        final showIndicator = active && _hoverInsertIndex != null;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(color: colorScheme.primary.withValues(alpha: 0.5))
                : null,
          ),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: widget.cards.isEmpty
                ? [
                    _EmptyColumnPlaceholder(
                      highlighted: active,
                      colorScheme: colorScheme,
                    ),
                  ]
                : [
                    for (var i = 0; i < widget.cards.length; i++) ...[
                      if (showIndicator && _hoverInsertIndex == i)
                        _InsertionIndicator(colorScheme: colorScheme),
                      KeyedSubtree(
                        key: _cardKeys[i],
                        child: KanbanCardTile(
                          columnId: widget.columnId,
                          card: widget.cards[i],
                          allColumns: widget.allColumns,
                          searchQuery: widget.searchQuery,
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

class _EmptyColumnPlaceholder extends StatelessWidget {
  const _EmptyColumnPlaceholder({
    required this.highlighted,
    required this.colorScheme,
  });

  final bool highlighted;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      alignment: Alignment.center,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted ? colorScheme.primary : colorScheme.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Text(
        '拖放卡片到此处',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
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
