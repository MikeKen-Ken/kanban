import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../features/project/project_theme.dart';
import '../../models/kanban_models.dart';
import 'card_detail_sheet.dart';
import 'kanban_labels.dart';

/// 单张看板卡片：勾选完成、拖动手柄、置顶、元数据展示
class KanbanCardTile extends StatelessWidget {
  const KanbanCardTile({
    super.key,
    required this.columnId,
    required this.card,
    required this.allColumns,
    this.searchQuery = '',
    this.isPinned = false,
    this.onDragStarted,
    this.onDragEnded,
  });

  final String columnId;
  final KanbanCard card;
  final List<KanbanColumn> allColumns;
  final String searchQuery;
  final bool isPinned;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BoardController>();
    final customLabels = controller.appSettings.customLabels;
    final usePointerDrag = controller.appSettings.usePointerDrag;
    final themeId = controller.projectSettings.themeId;

    if (!card.matchesSearch(searchQuery, customLabels: customLabels)) {
      return const SizedBox.shrink();
    }

    final feedback = Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 268,
        child: _CardContent(
          card: card,
          dragging: true,
          isPinned: isPinned,
          customLabels: customLabels,
          themeId: themeId,
        ),
      ),
    );

    final content = _CardContent(
      card: card,
      columnId: columnId,
      allColumns: allColumns,
      isPinned: isPinned,
      customLabels: customLabels,
      themeId: themeId,
      dragHandle: usePointerDrag
          ? null
          : _CardDragHandle(
              card: card,
              feedback: feedback,
              onDragStarted: onDragStarted,
              onDragEnded: onDragEnded,
            ),
    );

    if (!usePointerDrag) {
      return content;
    }

    if (controller.appSettings.immediateDrag) {
      return Draggable<KanbanCard>(
        data: card,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragEnded?.call(),
        feedback: feedback,
        childWhenDragging: Opacity(
          opacity: 0.25,
          child: content,
        ),
        child: content,
      );
    }

    return LongPressDraggable<KanbanCard>(
      data: card,
      delay: controller.appSettings.dragDelay,
      hapticFeedbackOnStart: true,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded?.call(),
      feedback: feedback,
      childWhenDragging: Opacity(
        opacity: 0.25,
        child: content,
      ),
      child: content,
    );
  }
}

class _CardDragHandle extends StatelessWidget {
  const _CardDragHandle({
    required this.card,
    required this.feedback,
    this.onDragStarted,
    this.onDragEnded,
  });

  final KanbanCard card;
  final Widget feedback;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BoardController>();
    final colorScheme = Theme.of(context).colorScheme;

    final handle = Tooltip(
      message: '长按手柄移动卡片',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              Icons.drag_indicator,
              size: 20,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );

    return LongPressDraggable<KanbanCard>(
      data: card,
      delay: controller.appSettings.dragDelay,
      hapticFeedbackOnStart: true,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded?.call(),
      feedback: feedback,
      childWhenDragging: Opacity(
        opacity: 0.25,
        child: handle,
      ),
      child: handle,
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.card,
    this.columnId,
    this.allColumns,
    this.dragging = false,
    this.isPinned = false,
    this.customLabels = const [],
    this.themeId = '',
    this.dragHandle,
  });

  final KanbanCard card;
  final String? columnId;
  final List<KanbanColumn>? allColumns;
  final bool dragging;
  final bool isPinned;
  final List<KanbanLabel> customLabels;
  final String themeId;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themePreset = projectThemeForId(themeId);
    final dueInfo = _dueDateInfo(card.dueDate, colorScheme);
    final cardColor =
        card.colorValue != null ? Color(card.colorValue!) : null;
    // note: 用 alphaBlend 得到不透明底色，避免半透明 Material 与 M3 surfaceTint 叠层盖住文字
    final cardBackground = cardColor != null
        ? Color.alphaBlend(
            cardColor.withValues(alpha: 0.18),
            colorScheme.surfaceContainerLow,
          )
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: cardColor != null ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPinned
            ? BorderSide(color: colorScheme.primary.withValues(alpha: 0.55))
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
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
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
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
                    if (isPinned)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.push_pin,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '已置顶',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (card.labels.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: card.labels.map((key) {
                            final label =
                                findKanbanLabel(key, customLabels, themeId);
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
                                  color: card.priority.color(
                                    colorScheme,
                                    theme: themePreset,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  card.priority.label,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: card.priority.color(
                                    colorScheme,
                                    theme: themePreset,
                                  ),
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
              if (!dragging && columnId != null)
                Column(
                  children: [
                    IconButton(
                      tooltip: isPinned ? '取消置顶' : '置顶',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => context
                          .read<BoardController>()
                          .toggleCardPin(columnId!, card.id),
                      icon: Icon(
                        isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                        size: 18,
                        color: isPinned
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.55),
                      ),
                    ),
                    if (dragHandle != null) dragHandle!,
                  ],
                )
              else if (dragHandle != null)
                dragHandle!,
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
