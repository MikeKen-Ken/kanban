import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../completed_auto_clear/completed_auto_clear.dart';
import 'card_complete_checkbox.dart';
import 'card_complete_motion.dart';
import 'card_copy_text.dart';
import 'card_detail_sheet.dart';
import 'card_drag.dart';
import 'kanban_card_context_menu.dart';
import 'card_tile_meta.dart';
import 'confirm_delete_card.dart';
import 'kanban_glass_surface.dart';
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

  /// 卡片上下文菜单（复制 / 克隆 / 转移到… / 删除）。
  ///
  /// 触发方式：
  /// - 桌面：右键（secondary tap）
  /// - Android / iOS：卡片「⋯」按钮；若设置为即时拖拽，亦可长按
  /// - 详情底栏「转移到…」：全平台可用（含默认延迟拖拽的 Android）
  Future<void> _showCardContextMenu(Offset globalPosition) async {
    if (!mounted || _dragStarted) return;
    final controller = context.read<BoardController>();
    final canTransfer = controller.projects.length > 1;
    final selected = await showKanbanCardContextMenu<String>(
      context: context,
      globalPosition: globalPosition,
      items: [
        const PopupMenuItem<String>(
          value: 'copy',
          child: Text('Copy'),
        ),
        const PopupMenuItem<String>(
          value: 'duplicate',
          child: Text('Clone'),
        ),
        PopupMenuItem<String>(
          value: 'transfer',
          enabled: canTransfer,
          child:
              Text(canTransfer ? 'Move to…' : 'Move to… (no other projects)'),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(
            'Delete',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
    if (!mounted) return;
    if (selected == 'copy') {
      await _copyCardWorkItems();
    } else if (selected == 'duplicate') {
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

  /// 把标题、备注、子任务、验证反馈和提交号复制为纯文本。
  Future<void> _copyCardWorkItems() async {
    await Clipboard.setData(
      ClipboardData(text: formatCardCopyText(widget.card)),
    );
    if (mounted) {
      showAppSnackBar(context, message: 'Card text copied');
    }
  }

  /// 在当前列克隆整张卡片，字段与附件均使用独立标识。
  Future<void> _duplicateCard() async {
    final copiedId = await context
        .read<BoardController>()
        .duplicateCard(widget.columnId, widget.card.id);
    if (copiedId == null && mounted) {
      showAppSnackBar(context, message: 'Clone failed: card not found');
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

  Future<void> _onToggleCompleted() async {
    final columnId = widget.columnId;
    final card = widget.card;
    final controller = context.read<BoardController>();
    if (card.completed) {
      final error = await controller.toggleCardCompleted(columnId, card.id);
      if (error != null && mounted) {
        showAppSnackBar(context, message: error);
      }
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    final fromRect = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : CardLayoutRegistry.instance.rectForCard(card.id);
    final board = controller.board;
    final doneColumnId = board == null
        ? null
        : findDoneColumn(
            board,
            doneColumnName: controller.projectSettings.doneColumnName,
          )?.id;

    final error = await playCardCompleteFlight(
      context: context,
      cardId: card.id,
      fromRect: fromRect,
      replica: KanbanCardFlightReplica(
        card: card,
        isPinned: widget.isPinned,
      ),
      doneColumnId: doneColumnId,
      mutate: () => controller.toggleCardCompleted(columnId, card.id),
    );
    if (error != null && mounted) {
      showAppSnackBar(context, message: error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visualSettings = context.select<
        BoardController,
        ({
          List<KanbanLabel> customLabels,
          String themeId,
          double cardSurfaceOpacity,
          int dragLongPressMs,
        })>(
      (value) => (
        customLabels: value.appSettings.customLabels,
        themeId: value.projectSettings.themeId,
        cardSurfaceOpacity: value.projectSettings.cardSurfaceOpacity,
        dragLongPressMs: value.appSettings.dragLongPressMs,
      ),
    );
    final customLabels = visualSettings.customLabels;
    final themeId = visualSettings.themeId;
    final cardSurfaceOpacity = visualSettings.cardSurfaceOpacity;
    final immediateDrag = visualSettings.dragLongPressMs <= 0;

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
          onToggleCompleted: _onToggleCompleted,
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

        // 右键只走上下文菜单，不进入拖拽手势竞技场，避免菜单被拖拽识别器卡住。
        bool primaryButtonOnly(int buttons) => buttons == kPrimaryButton;
        final Widget draggableChild = immediateDrag
            ? CardDraggable<KanbanCard>(
                data: widget.card,
                allowedButtonsFilter: primaryButtonOnly,
                dragAnchorStrategy: anchorStrategy,
                onDragStarted: _onDragStarted,
                onDragEnd: (_) => _onDragEnded(),
                feedback: feedback,
                childWhenDragging: childWhenDragging,
                child: content,
              )
            : CardLongPressDraggable<KanbanCard>(
                data: widget.card,
                allowedButtonsFilter: primaryButtonOnly,
                delay: Duration(milliseconds: visualSettings.dragLongPressMs),
                hapticFeedbackOnStart: true,
                dragAnchorStrategy: anchorStrategy,
                onDragStarted: _onDragStarted,
                onDragEnd: (_) => _onDragEnded(),
                feedback: feedback,
                childWhenDragging: childWhenDragging,
                child: content,
              );

        return CardContextMenuHost(
          onContextMenu: _showCardContextMenu,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            child: draggableChild,
          ),
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
    this.onToggleCompleted,
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
  final Future<void> Function()? onToggleCompleted;
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
    final isDark = theme.brightness == Brightness.dark;
    final glassEdge = isDark
        ? Colors.white.withValues(alpha: 0.20)
        : Colors.white.withValues(alpha: 0.58);
    final BorderSide cardOutline = hasConflict
        ? BorderSide(color: colorScheme.error, width: 1.5)
        : isPinned
            ? BorderSide(color: colorScheme.primary.withValues(alpha: 0.55))
            : BorderSide(color: glassEdge);
    return Padding(
      padding: dragging ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: kanbanGlassBlur(18),
          child: Card(
            // 拖拽反馈去掉列间距 margin；间距由外层 Padding 承担
            margin: EdgeInsets.zero,
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      color: colorScheme.errorContainer,
                      child: Text(
                        'Conflict',
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
                              CardDragInteractionBlocker(
                                child: CardCompleteCheckbox(
                                  value: card.completed,
                                  onChanged: (_) async {
                                    await onToggleCompleted?.call();
                                  },
                                ),
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
                                            'Pinned',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
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
                                              color: label.color
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  label.name,
                                                  style: theme
                                                      .textTheme.labelSmall
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
                                          return Tooltip(
                                              message: tip, child: chip);
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
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  if (dueInfo != null ||
                                      card.priority != CardPriority.none ||
                                      card.hasChecklist ||
                                      card.hasVerificationFeedback ||
                                      card.hasLinks ||
                                      card.hasBlockedBy ||
                                      card.hasRelated) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
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
                                                style: theme
                                                    .textTheme.labelSmall
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
                                          _CardMetaIconBadge(
                                            icon: Icons.checklist,
                                            label:
                                                '${card.checklistDone}/${card.checklist.length}',
                                            colorScheme: colorScheme,
                                            textTheme: theme.textTheme,
                                          ),
                                        if (card.hasVerificationFeedback)
                                          _CardMetaIconBadge(
                                            icon: Icons.fact_check_outlined,
                                            label:
                                                '${card.verificationFeedbackDone}/${card.verificationFeedback.length}',
                                            colorScheme: colorScheme,
                                            textTheme: theme.textTheme,
                                          ),
                                        if (card.hasLinks)
                                          _CardMetaIconBadge(
                                            icon: Icons.link,
                                            label: '${card.links.length}',
                                            colorScheme: colorScheme,
                                            textTheme: theme.textTheme,
                                          ),
                                        if (card.hasBlockedBy)
                                          _CardMetaIconBadge(
                                            icon: Icons.block_outlined,
                                            label: _blockedByCountLabel(),
                                            colorScheme: colorScheme,
                                            textTheme: theme.textTheme,
                                          ),
                                        if (card.hasRelated)
                                          _CardMetaIconBadge(
                                            icon: Icons.account_tree_outlined,
                                            colorScheme: colorScheme,
                                            textTheme: theme.textTheme,
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // 操作列：置顶在上，三点菜单紧挨其正下方，尽量不拉宽卡片横向布局
                            if (!dragging && columnId != null)
                              CardDragInteractionBlocker(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: isPinned ? 'Unpin' : 'Pin',
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
                                    if (showContextMenuButton &&
                                        onContextMenu != null)
                                      Builder(
                                        builder: (buttonContext) {
                                          return IconButton(
                                            key: const ValueKey(
                                                'card-context-menu-button'),
                                            tooltip: 'More (move/delete)',
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 28,
                                              minHeight: 28,
                                            ),
                                            onPressed: () {
                                              final box = buttonContext
                                                      .findRenderObject()
                                                  as RenderBox?;
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
                                              color: colorScheme
                                                  .onSurfaceVariant
                                                  .withValues(alpha: 0.55),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
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
          ),
        ),
      ),
    );
  }

  /// 右下角「更新于」文案；无效时间戳不展示。
  String? _updatedAtLabel() {
    final formatted = formatSmartCompactDateTime(card.updatedAt);
    if (formatted == null) return null;
    return 'Updated $formatted';
  }

  /// 依赖计数：能解析前置卡时展示「已完成/总数」，否则仅展示总数。
  String? _blockedByCountLabel() {
    final total = card.blockedByIds.length;
    final columns = allColumns;
    if (columns == null) return '$total';
    final done = countCompletedBlockedBy(
      blockedByIds: card.blockedByIds,
      columns: columns,
    );
    return '$done/$total';
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
        !card.hasVerificationFeedback &&
        !card.hasLinks &&
        !card.hasBlockedBy &&
        !card.hasRelated;
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

/// 卡片元信息图标徽标；[label] 为空时仅展示图标（用于无数量概念的状态）。
class _CardMetaIconBadge extends StatelessWidget {
  const _CardMetaIconBadge({
    required this.icon,
    required this.colorScheme,
    required this.textTheme,
    this.label,
  });

  final IconData icon;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        if (label != null) ...[
          const SizedBox(width: 2),
          Text(label!, style: textTheme.labelSmall),
        ],
      ],
    );
  }
}

/// 完成飞行 Overlay 使用的卡片副本：已完成态、无交互。
class KanbanCardFlightReplica extends StatelessWidget {
  const KanbanCardFlightReplica({
    super.key,
    required this.card,
    this.isPinned = false,
  });

  final KanbanCard card;
  final bool isPinned;

  @override
  Widget build(BuildContext context) {
    final visualSettings = context.select<
        BoardController,
        ({
          List<KanbanLabel> customLabels,
          String themeId,
          double cardSurfaceOpacity,
        })>(
      (value) => (
        customLabels: value.appSettings.customLabels,
        themeId: value.projectSettings.themeId,
        cardSurfaceOpacity: value.projectSettings.cardSurfaceOpacity,
      ),
    );
    return _CardContent(
      card: card.copyWith(completed: true),
      dragging: true,
      isPinned: isPinned,
      customLabels: visualSettings.customLabels,
      themeId: visualSettings.themeId,
      surfaceOpacity: visualSettings.cardSurfaceOpacity,
    );
  }
}
