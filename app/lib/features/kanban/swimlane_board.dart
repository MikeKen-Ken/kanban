import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../common/app_snack_bar.dart';
import '../../models/kanban_models.dart';
import '../../widgets/kanban_column_widget.dart';
import 'board_horizontal_scroll.dart';
import 'swimlane.dart';

/// 按泳道横向排列各列的看板主体。
class SwimlaneBoard extends StatelessWidget {
  const SwimlaneBoard({
    super.key,
    required this.board,
    required this.visibleCardIds,
    required this.mode,
    this.compact = false,
  });

  final KanbanBoard board;
  final Set<String> visibleCardIds;
  final SwimlaneMode mode;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BoardController>();
    const service = SwimlaneService();
    final allCards = board.columns.expand((c) => c.cards);
    final buckets = service.bucketsFor(
      mode: mode,
      cards: allCards,
      customLabels: controller.appSettings.customLabels,
      themeId: controller.projectSettings.themeId,
    );
    final laneHeight = compact ? 360.0 : 420.0;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: buckets.length,
      itemBuilder: (context, index) {
        final bucket = buckets[index];
        return _SwimlaneRow(
          bucket: bucket,
          mode: mode,
          board: board,
          visibleCardIds: visibleCardIds,
          height: laneHeight,
          compact: compact,
        );
      },
    );
  }
}

class _SwimlaneRow extends StatelessWidget {
  const _SwimlaneRow({
    required this.bucket,
    required this.mode,
    required this.board,
    required this.visibleCardIds,
    required this.height,
    required this.compact,
  });

  final SwimlaneBucket bucket;
  final SwimlaneMode mode;
  final KanbanBoard board;
  final Set<String> visibleCardIds;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const service = SwimlaneService();
    final controller = context.read<BoardController>();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              bucket.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            height: height,
            child: KanbanHorizontalScrollConfiguration(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: board.columns.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final column = board.columns[index];
                  final laneCardIds = column.cards
                      .where(
                        (card) =>
                            visibleCardIds.contains(card.id) &&
                            service.cardMatches(card, bucket, mode),
                      )
                      .map((card) => card.id)
                      .toSet();
                  return DragTarget<KanbanCard>(
                    onWillAcceptWithDetails: (_) => true,
                    onAcceptWithDetails: (details) async {
                      final card = details.data;
                      String? fromColumnId;
                      for (final col in board.columns) {
                        if (col.cards.any((c) => c.id == card.id)) {
                          fromColumnId = col.id;
                          break;
                        }
                      }
                      if (fromColumnId == null) return;
                      final updated = service.applyBucket(card, bucket, mode);
                      if (updated.priority != card.priority ||
                          !_sameLabels(updated.labels, card.labels)) {
                        await controller.updateCardFull(
                          fromColumnId,
                          card.id,
                          priority: updated.priority,
                          labels: updated.labels,
                        );
                      }
                      if (fromColumnId != column.id) {
                        final error = await controller.moveCard(
                          cardId: card.id,
                          fromColumnId: fromColumnId,
                          toColumnId: column.id,
                          toDisplayIndex: column.cards.length,
                        );
                        if (error != null && context.mounted) {
                          showAppSnackBar(context, message: error);
                        }
                      }
                    },
                    builder: (context, candidate, _) {
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: candidate.isNotEmpty
                              ? Border.all(
                                  color: theme.colorScheme.primary,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: KanbanColumnWidget(
                          column: column,
                          columnIndex: index,
                          visibleCardIds: laneCardIds,
                          width: compact
                              ? MediaQuery.sizeOf(context).width - 48
                              : 280,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _sameLabels(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
