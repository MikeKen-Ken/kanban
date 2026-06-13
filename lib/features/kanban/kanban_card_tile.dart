import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import 'card_detail_sheet.dart';
import 'kanban_labels.dart';

/// 单张看板卡片：勾选完成、拖拽、元数据展示
class KanbanCardTile extends StatelessWidget {  const KanbanCardTile({
    super.key,
    required this.columnId,
    required this.card,
    required this.allColumns,
    this.searchQuery = '',
    this.onDragStarted,
    this.onDragEnded,
  });

  final String columnId;
  final KanbanCard card;
  final List<KanbanColumn> allColumns;
  final String searchQuery;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;

  @override
  Widget build(BuildContext context) {
    if (!card.matchesSearch(searchQuery)) {
      return const SizedBox.shrink();
    }

    final appSettings = context.watch<BoardController>().appSettings;
    final immediateDrag = appSettings.immediateDrag;

    final content = _CardContent(
      card: card,
      columnId: columnId,
      allColumns: allColumns,
      showDragHint: !immediateDrag,
      dragHintMs: appSettings.dragLongPressMs,
    );
    final feedback = Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 268,
        child: _CardContent(card: card, dragging: true),
      ),
    );
    final childWhenDragging = Opacity(
      opacity: 0.35,
      child: _CardContent(card: card),
    );

    if (immediateDrag) {
      return Draggable<KanbanCard>(
        data: card,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragEnded?.call(),
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        child: content,
      );
    }

    return LongPressDraggable<KanbanCard>(
      data: card,
      delay: appSettings.dragDelay,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded?.call(),
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      child: content,
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.card,
    this.columnId,
    this.allColumns,
    this.dragging = false,
    this.showDragHint = false,
    this.dragHintMs = 500,
  });

  final KanbanCard card;
  final String? columnId;
  final List<KanbanColumn>? allColumns;
  final bool dragging;
  final bool showDragHint;
  final int dragHintMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dueInfo = _dueDateInfo(card.dueDate, colorScheme);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: dragging || columnId == null
            ? null
            : () => showCardDetailSheet(
                  context: context,
                  columnId: columnId!,
                  card: card,
                ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (columnId != null)
                Checkbox(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  value: card.completed,
                  onChanged: (_) => context
                      .read<BoardController>()
                      .toggleCardCompleted(columnId!, card.id),
                )
              else
                const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (card.labels.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: card.labels.map((key) {
                            final label = findKanbanLabel(key);
                            if (label == null) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: label.color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                label.name,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: label.color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    Text(
                      card.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        decoration: card.completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: card.completed
                            ? colorScheme.onSurface.withValues(alpha: 0.5)
                            : null,
                      ),
                    ),
                    if (card.description != null &&
                        card.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        card.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (dueInfo != null ||
                        card.priority != CardPriority.none ||
                        card.hasChecklist) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (dueInfo != null) dueInfo,
                          if (card.priority != CardPriority.none)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.flag,
                                  size: 14,
                                  color: card.priority.color(colorScheme),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  card.priority.label,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: card.priority.color(colorScheme),
                                  ),
                                ),
                              ],
                            ),
                          if (card.hasChecklist)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.checklist,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${card.checklistDone}/${card.checklist.length}',
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (!dragging)
                Tooltip(
                  message: showDragHint
                      ? '长按 ${dragHintMs}ms 拖动'
                      : '拖动',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, top: 4),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _dueDateInfo(int? dueMs, ColorScheme scheme) {
    if (dueMs == null) return null;
    final due = DateTime.fromMillisecondsSinceEpoch(dueMs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    final overdue = !card.completed && dueDay.isBefore(today);
    final color = overdue ? scheme.error : scheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule, size: 14, color: color),
        const SizedBox(width: 2),
        Text(
          DateFormat.MMMd('zh_CN').format(due),
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: overdue ? FontWeight.w600 : null,
          ),
        ),
      ],
    );
  }
}
