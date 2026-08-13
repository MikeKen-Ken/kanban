import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../common/app_snack_bar.dart';
import '../../common/date_utils.dart';
import '../../controllers/board_controller.dart';
import '../../features/project/project_settings.dart';
import '../../features/project/project_theme.dart';
import '../../models/kanban_models.dart';
import '../attachments/card_attachment_image.dart';
import '../attachments/card_attachment_viewer.dart';
import 'card_detail_sheet.dart';
import 'card_drag.dart';
import 'confirm_delete_card.dart';
import 'kanban_labels.dart';
import 'markdown_plain_text.dart';
import 'transfer_card_sheet.dart';

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

  /// 卡片上下文菜单（复制 / 转移到… / 删除）。
  ///
  /// 触发方式：
  /// - 桌面：右键（secondary tap）
  /// - Android / iOS：卡片「⋯」按钮；若设置为即时拖拽，亦可长按
  /// - 详情底栏「转移到…」：全平台可用（含默认延迟拖拽的 Android）
  Future<void> _showCardContextMenu(Offset globalPosition) async {
    if (!mounted || _dragStarted) return;
    final controller = context.read<BoardController>();
    final canTransfer = controller.projects.length > 1;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final overlaySize = overlay?.size ?? MediaQuery.sizeOf(context);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlaySize.width - globalPosition.dx,
        overlaySize.height - globalPosition.dy,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'duplicate',
          child: Text('复制'),
        ),
        PopupMenuItem<String>(
          value: 'transfer',
          enabled: canTransfer,
          child: Text(canTransfer ? '转移到…' : '转移到…（无其他项目）'),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(
            '删除',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
    if (!mounted) return;
    if (selected == 'duplicate') {
      await _duplicateCard();
    } else if (selected == 'transfer') {
      await showTransferCardToProjectFlow(
        context: context,
        columnId: widget.columnId,
        cardId: widget.card.id,
        cardTitle: widget.card.title,
      );
    } else if (selected == 'delete') {
      await _confirmAndDeleteCard();
    }
  }

  /// 在当前列创建副本，字段与附件均使用独立标识。
  Future<void> _duplicateCard() async {
    final copiedId = await context
        .read<BoardController>()
        .duplicateCard(widget.columnId, widget.card.id);
    if (copiedId == null && mounted) {
      showAppSnackBar(context, message: '复制失败：卡片不存在');
    }
  }

  /// 与详情页删除一致：按本机偏好确认后移入回收站。
  Future<void> _confirmAndDeleteCard() async {
    final controller = context.read<BoardController>();
    final ok = await confirmDeleteCardIfNeeded(
      context: context,
      cardTitle: widget.card.title,
      confirmBeforeDelete: controller.appSettings.confirmBeforeDeleteCard,
    );
    if (ok && mounted) {
      await controller.deleteCard(widget.columnId, widget.card.id);
    }
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

        final touchMenuButton = shouldShowCardContextMenuButton(
          Theme.of(context).platform,
        );
        final content = _CardContent(
          card: widget.card,
          columnId: widget.columnId,
          allColumns: widget.allColumns,
          isPinned: widget.isPinned,
          customLabels: customLabels,
          themeId: themeId,
          surfaceOpacity: cardSurfaceOpacity,
          // 关掉按下水波/高亮：半透明卡面下 ink 会像「下方多一层」；
          // 延迟拖拽时也避免「填充动画」误导成已可拖
          suppressInk: true,
          onOpenDetail: _openDetail,
          onContextMenu: _showCardContextMenu,
          // 默认延迟拖拽：长按启动拖拽，Android 靠「⋯」；即时拖拽才用长按开菜单
          enableLongPressContextMenu: shouldEnableLongPressCardContextMenu(
            immediateDrag: immediateDrag,
          ),
          showContextMenuButton: touchMenuButton,
        );

        // 拖起后原位只保留占位尺寸，不绘制幽灵卡面，避免与反馈层叠成两层
        final childWhenDragging = Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: content,
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
                childWhenDragging: childWhenDragging,
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
                childWhenDragging: childWhenDragging,
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
    this.onContextMenu,
    this.enableLongPressContextMenu = false,
    this.showContextMenuButton = false,
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
  final void Function(Offset globalPosition)? onContextMenu;
  final bool enableLongPressContextMenu;

  /// Android / iOS：显式「⋯」入口（见 [shouldShowCardContextMenuButton]）
  final bool showContextMenuButton;

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
    final cardColor = card.colorValue != null ? Color(card.colorValue!) : null;
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
      margin: dragging ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
      color: cardBackground,
      surfaceTintColor: Colors.transparent,
      // 仅反馈层抬升阴影；列表态 elevation 0，避免本体再垫一层阴影板
      elevation: dragging ? 6 : 0,
      shadowColor: Colors.black54,
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
        hoverColor: suppressInk ? Colors.transparent : null,
        focusColor: suppressInk ? Colors.transparent : null,
        onTap: dragging || columnId == null || onOpenDetail == null
            ? null
            : onOpenDetail,
        onSecondaryTapDown:
            dragging || columnId == null || onContextMenu == null
                ? null
                : (details) => onContextMenu!(details.globalPosition),
        onLongPress: dragging ||
                columnId == null ||
                onContextMenu == null ||
                !enableLongPressContextMenu
            ? null
            : () {
                // 长按无精确落点时，以卡片中心为菜单锚点
                final box = context.findRenderObject() as RenderBox?;
                if (box == null || !box.hasSize) return;
                final center = box.size.center(Offset.zero);
                onContextMenu!(box.localToGlobal(center));
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasConflict)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    // note: 仅标题时与勾选框垂直居中；有标签/描述等时仍顶对齐
                    crossAxisAlignment:
                        _isTitleOnlyContent(dueInfo, descriptionSummary)
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                    children: [
                      if (columnId != null)
                        _CardCompleteCheckbox(
                          value: card.completed,
                          onChanged: (_) async {
                            final error = await context
                                .read<BoardController>()
                                .toggleCardCompleted(columnId!, card.id);
                            if (error != null && context.mounted) {
                              showAppSnackBar(context, message: error);
                            }
                          },
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
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
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
                                    final chip = Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            label.color.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            label.name,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: label.color,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    final tip = label.description;
                                    if (tip == null || tip.isEmpty) {
                                      return chip;
                                    }
                                    return Tooltip(message: tip, child: chip);
                                  }).toList(),
                                ),
                              ),
                            Text(
                              card.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                height: 1.25,
                                leadingDistribution:
                                    TextLeadingDistribution.even,
                                decoration: card.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: card.completed
                                    ? colorScheme.onSurface
                                        .withValues(alpha: 0.5)
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
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
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
                      // 操作列：置顶在上，三点菜单紧挨其正下方，尽量不拉宽卡片横向布局
                      if (!dragging && columnId != null)
                        Column(
                          mainAxisSize: MainAxisSize.min,
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
                                isPinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 18,
                                color: isPinned
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.55),
                              ),
                            ),
                            if (showContextMenuButton && onContextMenu != null)
                              Builder(
                                builder: (buttonContext) {
                                  return IconButton(
                                    key: const ValueKey(
                                        'card-context-menu-button'),
                                    tooltip: '更多（转移/删除）',
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    onPressed: () {
                                      final box = buttonContext
                                          .findRenderObject() as RenderBox?;
                                      if (box == null || !box.hasSize) {
                                        return;
                                      }
                                      final anchor = box.localToGlobal(
                                        box.size.center(Offset.zero),
                                      );
                                      onContextMenu!(anchor);
                                    },
                                    icon: Icon(
                                      Icons.more_vert,
                                      size: 18,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.55),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                    ],
                  ),
                  if (_updatedAtLabel() case final updatedLabel?) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          updatedLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.72),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右下角「更新于」文案；无效时间戳不展示。
  String? _updatedAtLabel() {
    final formatted = formatSmartCompactDateTime(card.updatedAt);
    if (formatted == null) return null;
    return '更新于 $formatted';
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

/// 卡片左侧完成勾选：点击缩放反馈，并吞掉长按以免触发整卡拖拽/选中。
class _CardCompleteCheckbox extends StatefulWidget {
  const _CardCompleteCheckbox({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  State<_CardCompleteCheckbox> createState() => _CardCompleteCheckboxState();
}

class _CardCompleteCheckboxState extends State<_CardCompleteCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scale;
  bool _handlingTap = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(begin: 1, end: 0.88).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _handleChanged(bool? next) async {
    if (_handlingTap || next == null) return;
    _handlingTap = true;
    try {
      // 先完成按下缩放，再切换完成态；避免列间移动销毁本组件时动画中途被打断。
      await _scaleController.forward();
      if (!mounted) {
        widget.onChanged(next);
        return;
      }
      widget.onChanged(next);
      if (mounted) {
        await _scaleController.reverse();
      }
    } finally {
      _handlingTap = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {},
      child: ScaleTransition(
        scale: _scale,
        child: Checkbox(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          value: widget.value,
          onChanged: _handleChanged,
        ),
      ),
    );
  }
}
