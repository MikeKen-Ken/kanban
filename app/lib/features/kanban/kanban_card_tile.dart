import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../features/project/project_settings.dart';
import '../../features/project/project_theme.dart';
import '../../models/kanban_models.dart';
import '../attachments/card_attachment_image.dart';
import '../attachments/card_attachment_viewer.dart';
import 'card_detail_sheet.dart';
import 'card_drag.dart';
import 'kanban_labels.dart';
import 'markdown_plain_text.dart';

/// 单张看板卡片：勾选完成、拖拽、置顶、元数据展示
class KanbanCardTile extends StatefulWidget {
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
  State<KanbanCardTile> createState() => _KanbanCardTileState();
}

class _KanbanCardTileState extends State<KanbanCardTile> {
  int? _pointerDownMs;
  bool _dragStarted = false;
  bool _blockTap = false;

  void _onPointerDown(PointerDownEvent event) {
    _pointerDownMs = DateTime.now().millisecondsSinceEpoch;
    _dragStarted = false;
    _blockTap = false;
  }

  void _onDragStarted() {
    _dragStarted = true;
    _blockTap = true;
    widget.onDragStarted?.call();
  }

  void _onDragEnded() {
    widget.onDragEnded?.call();
  }

  void _openDetail() {
    if (_blockTap || _dragStarted) return;
    final down = _pointerDownMs;
    if (down != null) {
      final heldMs = DateTime.now().millisecondsSinceEpoch - down;
      final settings = context.read<BoardController>().appSettings;
      if (shouldSuppressCardTapAfterPress(
        heldMs: heldMs,
        dragLongPressMs: settings.dragLongPressMs,
        dragStarted: _dragStarted,
      )) {
        return;
      }
    }
    showCardDetailSheet(
      context: context,
      columnId: widget.columnId,
      card: widget.card,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BoardController>();
    final customLabels = controller.appSettings.customLabels;
    final themeId = controller.projectSettings.themeId;
    final cardSurfaceOpacity = controller.projectSettings.cardSurfaceOpacity;
    final immediateDrag = controller.appSettings.immediateDrag;

    if (!widget.card
        .matchesSearch(widget.searchQuery, customLabels: customLabels)) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final feedbackWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 268.0;

        // 反馈层只用同一套 _CardContent，避免外包 Material 造成套层与尺寸偏差
        final feedback = SizedBox(
          width: feedbackWidth,
          child: _CardContent(
            card: widget.card,
            dragging: true,
            isPinned: widget.isPinned,
            customLabels: customLabels,
            themeId: themeId,
            surfaceOpacity: cardSurfaceOpacity,
          ),
        );

        final content = _CardContent(
          card: widget.card,
          columnId: widget.columnId,
          allColumns: widget.allColumns,
          isPinned: widget.isPinned,
          customLabels: customLabels,
          themeId: themeId,
          surfaceOpacity: cardSurfaceOpacity,
          // 延迟拖拽时关掉按下水波，避免「填充动画」误导成已可拖
          suppressInk: !immediateDrag,
          onOpenDetail: _openDetail,
        );

        Offset anchorStrategy(
          Draggable<Object> draggable,
          BuildContext ctx,
          Offset position,
        ) {
          return feedbackCenterDragAnchorStrategy(
            draggable,
            ctx,
            position,
            feedbackWidth: feedbackWidth,
            // 列表卡片有 bottom: 8 间距；反馈层 margin 为 0
            listBottomMargin: 8,
          );
        }

        final Widget draggableChild = immediateDrag
            ? Draggable<KanbanCard>(
                data: widget.card,
                dragAnchorStrategy: anchorStrategy,
                onDragStarted: _onDragStarted,
                onDragEnd: (_) => _onDragEnded(),
                feedback: feedback,
                childWhenDragging: Opacity(
                  opacity: 0.25,
                  child: content,
                ),
                child: content,
              )
            : CardLongPressDraggable<KanbanCard>(
                data: widget.card,
                delay: controller.appSettings.dragDelay,
                hapticFeedbackOnStart: true,
                dragAnchorStrategy: anchorStrategy,
                onDragStarted: _onDragStarted,
                onDragEnd: (_) => _onDragEnded(),
                feedback: feedback,
                childWhenDragging: Opacity(
                  opacity: 0.25,
                  child: content,
                ),
                child: content,
              );

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          child: draggableChild,
        );
      },
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
    this.surfaceOpacity = ProjectSettings.defaultCardSurfaceOpacity,
    this.suppressInk = false,
    this.onOpenDetail,
  });

  final KanbanCard card;
  final String? columnId;
  final List<KanbanColumn>? allColumns;
  final bool dragging;
  final bool isPinned;
  final List<KanbanLabel> customLabels;
  final String themeId;
  final double surfaceOpacity;
  final bool suppressInk;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themePreset = projectThemeForId(themeId);
    final dueInfo = _dueDateInfo(card.dueDate, colorScheme);
    final plainDescription = markdownToPlainText(card.description ?? '');
    final descriptionSummary =
        plainDescription.isEmpty ? null : plainDescription;
    final cover = card.coverAttachment;
    final extraImageCount =
        card.attachments.length > 1 ? card.attachments.length - 1 : 0;
    final cardColor =
        card.colorValue != null ? Color(card.colorValue!) : null;
    final opacity = ProjectSettings.clampCardSurfaceOpacity(surfaceOpacity);
    // note: 卡片底色带不透明度，降低后可透过整张卡片看到壁纸；文字仍用不透明前景色
    final solidBackground = cardColor != null
        ? Color.alphaBlend(
            cardColor.withValues(alpha: 0.18),
            colorScheme.surface,
          )
        : colorScheme.surface;
    final cardBackground = solidBackground.withValues(alpha: opacity);

    final hasConflict = card.hasConflict;
    final BorderSide cardOutline = hasConflict
        ? BorderSide(color: colorScheme.error, width: 1.5)
        : isPinned
            ? BorderSide(color: colorScheme.primary.withValues(alpha: 0.55))
            : BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.95),
              );
    return Card(
      // 拖拽反馈去掉列间距 margin，尺寸与可见卡片本体一致
      margin: dragging
          ? EdgeInsets.zero
          : const EdgeInsets.only(bottom: 8),
      color: cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: cardOutline,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        splashFactory: suppressInk ? NoSplash.splashFactory : null,
        highlightColor: suppressInk ? Colors.transparent : null,
        splashColor: suppressInk ? Colors.transparent : null,
        onTap: dragging || columnId == null || onOpenDetail == null
            ? null
            : onOpenDetail,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasConflict)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                color: colorScheme.errorContainer,
                child: Text(
                  '冲突',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (cover != null)
              GestureDetector(
                onTap: dragging
                    ? null
                    : () => showCardAttachmentViewer(
                          context: context,
                          attachments: card.sortedAttachments,
                          initialIndex: 0,
                        ),
                child: SizedBox(
                  height: 132,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CardAttachmentImage(
                        attachmentId: cover.id,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      if (extraImageCount > 0)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '+$extraImageCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                // note: 仅标题时与勾选框垂直居中；有标签/描述等时仍顶对齐
                crossAxisAlignment: _isTitleOnlyContent(dueInfo, descriptionSummary)
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
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
                      mainAxisSize: MainAxisSize.min,
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
                                final label = findKanbanLabel(
                                    key, customLabels, themeId);
                                if (label == null) {
                                  return const SizedBox.shrink();
                                }
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
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
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
                            height: 1.25,
                            leadingDistribution: TextLeadingDistribution.even,
                            decoration: card.completed
                                ? TextDecoration.lineThrough
                                : null,
                            color: card.completed
                                ? colorScheme.onSurface.withValues(alpha: 0.5)
                                : null,
                          ),
                        ),
                        if (descriptionSummary != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            descriptionSummary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (dueInfo != null ||
                            card.priority != CardPriority.none ||
                            card.hasChecklist ||
                            card.hasLinks ||
                            card.hasRelations) ...[
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
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
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
                              if (card.hasLinks)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.link,
                                      size: 14,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${card.links.length}',
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              if (card.hasRelations)
                                Icon(
                                  Icons.account_tree_outlined,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!dragging && columnId != null)
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 仅标题（无置顶徽标/标签/描述/元信息）时，与勾选框垂直居中
  bool _isTitleOnlyContent(Widget? dueInfo, String? descriptionSummary) {
    final hasDescription = descriptionSummary != null;
    return !isPinned &&
        card.labels.isEmpty &&
        !hasDescription &&
        dueInfo == null &&
        card.priority == CardPriority.none &&
        !card.hasChecklist &&
        !card.hasLinks &&
        !card.hasRelations;
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
