import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/board_controller.dart';
import '../features/kanban/card_detail_sheet.dart';
import '../features/kanban/column_card_preferences.dart';
import '../features/kanban/kanban_column_list.dart';
import '../models/kanban_models.dart';
import '../settings/column_color_picker.dart';
import '../common/app_snack_bar.dart';

class KanbanColumnWidget extends StatelessWidget {
  const KanbanColumnWidget({
    super.key,
    required this.column,
    required this.columnIndex,
    this.searchQuery = '',
    this.visibleCardIds,
    this.width = 300,
  });

  final KanbanColumn column;
  final int columnIndex;
  final String searchQuery;
  final Set<String>? visibleCardIds;
  final double width;

  List<KanbanCard> _displayCards(BoardController controller) {
    final cards = controller.displayCardsForColumn(column);
    final visible = visibleCardIds;
    return visible == null
        ? cards
        : cards.where((card) => visible.contains(card.id)).toList();
  }

  Future<void> _pickSortMode(BuildContext context) async {
    final controller = context.read<BoardController>();
    final prefs = controller.columnPreferencesFor(column.id);
    final picked = await showModalBottomSheet<CardSortMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '「${column.title}」排序方式',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final mode in CardSortMode.values)
              ListTile(
                leading: Icon(
                  prefs.sortMode == mode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(mode.label),
                subtitle: mode == CardSortMode.custom
                    ? const Text('拖动手柄自由排序，顺序会保留')
                    : null,
                onTap: () => Navigator.pop(ctx, mode),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && picked != prefs.sortMode) {
      await controller.setColumnSortMode(column.id, picked);
    }
  }

  /// 先落库再建卡，再打开与点击卡片相同的详情页编辑。
  Future<void> _addCard(BuildContext context) async {
    final controller = context.read<BoardController>();

    // 有模板时先选创建方式，避免丢掉「从模板」入口。
    if (controller.cardTemplates.isNotEmpty) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  '在「${column.title}」添加卡片',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('空白卡片'),
                subtitle: const Text('创建后打开详情编辑'),
                onTap: () => Navigator.pop(ctx, 'blank'),
              ),
              ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: const Text('从模板'),
                onTap: () => Navigator.pop(ctx, 'template'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (choice == null || !context.mounted) return;
      if (choice == 'template') {
        await _addCardFromTemplate(context, controller);
        return;
      }
    }

    final cardId = await controller.addCard(column.id, '');
    if (!context.mounted) return;
    await _openCreatedCardDetail(context, controller, cardId);
  }

  Future<void> _addCardFromTemplate(
    BuildContext context,
    BoardController controller,
  ) async {
    final templateId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择卡片模板'),
        children: [
          for (final template in controller.cardTemplates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, template.id),
              child: Text(template.name),
            ),
        ],
      ),
    );
    if (templateId == null || !context.mounted) return;
    final cardId = await controller.createCardFromTemplate(
      templateId: templateId,
      columnId: column.id,
    );
    if (!context.mounted) return;
    await _openCreatedCardDetail(context, controller, cardId);
  }

  Future<void> _openCreatedCardDetail(
    BuildContext context,
    BoardController controller,
    String? cardId,
  ) async {
    if (cardId == null) return;
    final card = controller.board?.columns
        .where((col) => col.id == column.id)
        .expand((col) => col.cards)
        .where((c) => c.id == cardId)
        .firstOrNull;
    if (card == null || !context.mounted) return;

    await showCardDetailSheet(
      context: context,
      columnId: column.id,
      card: card,
      autofocusTitle: true,
    );
  }

  Future<void> _renameColumn(BuildContext context) async {
    final controller = context.read<BoardController>();
    final textController = TextEditingController(text: column.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名列'),
        content: TextField(
          controller: textController,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) {
      await controller.renameColumn(column.id, title);
    }
  }

  Future<void> _confirmDeleteColumn(BuildContext context) async {
    final controller = context.read<BoardController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除列？'),
        content: Text('将删除「${column.title}」及其全部卡片，并移至回收站'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteColumn(column.id);
    }
  }

  Future<void> _confirmClearDoneColumn(BuildContext context) async {
    final controller = context.read<BoardController>();
    final count = column.cards.length;
    if (count == 0) {
      showAppSnackBar(context, message: '已完成列为空，无需清空');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空已完成列？'),
        content: Text('将「${column.title}」中的 $count 张卡片移至回收站'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final cleared = await controller.clearDoneColumnCards(column.id);
    if (!context.mounted) return;
    showAppSnackBar(context, message: cleared > 0 ? '已清空 $cleared 张卡片' : '清空失败');
  }

  Future<void> _pickColumnColor(BuildContext context) async {
    final controller = context.read<BoardController>();
    final picked = await showColumnColorPicker(
      context: context,
      currentColorValue: column.colorValue,
      title: '列颜色',
    );
    if (picked == column.colorValue) return;
    await controller.updateColumnColor(column.id, picked);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = context.watch<BoardController>();
    final columnColor =
        column.colorValue != null ? Color(column.colorValue!) : null;
    final cards = _displayCards(controller);
    final columnPrefs = controller.columnPreferencesFor(column.id);
    final wipLimit = controller.projectSettings.wipLimitFor(column.id);
    final activeCount = column.cards.where((card) => !card.completed).length;
    final overWip = wipLimit != null && activeCount > wipLimit;
    final allColumns = controller.board?.columns ?? [];
    final customLabels = controller.appSettings.customLabels;
    final visibleCount = cards
        .where((c) => c.matchesSearch(searchQuery, customLabels: customLabels))
        .length;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: columnColor != null
            ? columnColor.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: overWip
              ? colorScheme.error
              : (columnColor ?? colorScheme.outlineVariant),
          width: overWip || columnColor != null ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (columnColor != null) ...[
                        Container(
                          width: 4,
                          height: 20,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: columnColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          column.title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: columnColor,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: wipLimit == null
                      ? '卡片数量'
                      : '未完成 $activeCount / 建议上限 $wipLimit'
                          '${overWip ? '，已超出' : ''}',
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: overWip
                          ? colorScheme.errorContainer
                          : colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      wipLimit == null
                          ? (searchQuery.isEmpty
                              ? '${cards.length}'
                              : '$visibleCount/${cards.length}')
                          : '$activeCount/$wipLimit',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color:
                                overWip ? colorScheme.onErrorContainer : null,
                            fontWeight: overWip ? FontWeight.w700 : null,
                          ),
                    ),
                  ),
                ),
                ReorderableDragStartListener(
                  index: columnIndex,
                  child: Tooltip(
                    message: '拖动调整列顺序',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.drag_indicator,
                          size: 20,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'sort':
                        _pickSortMode(context);
                      case 'color':
                        _pickColumnColor(context);
                      case 'rename':
                        _renameColumn(context);
                      case 'clear_done':
                        _confirmClearDoneColumn(context);
                      case 'delete':
                        _confirmDeleteColumn(context);
                    }
                  },
                  itemBuilder: (_) {
                    final isDone = controller.isDoneColumn(column.id);
                    return [
                      PopupMenuItem(
                        value: 'sort',
                        child: Text('排序：${columnPrefs.sortMode.label}'),
                      ),
                      const PopupMenuItem(value: 'color', child: Text('设置颜色')),
                      const PopupMenuItem(value: 'rename', child: Text('重命名')),
                      if (isDone)
                        const PopupMenuItem(
                          value: 'clear_done',
                          child: Text('一键清空'),
                        ),
                      const PopupMenuItem(value: 'delete', child: Text('删除列')),
                    ];
                  },
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: (columnColor ?? colorScheme.outlineVariant)
                .withValues(alpha: 0.35),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: OutlinedButton.icon(
              onPressed: () => _addCard(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加卡片'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: KanbanColumnList(
                  columnId: column.id,
                  cards: cards,
                  allColumns: allColumns,
                  searchQuery: searchQuery,
                  sortMode: columnPrefs.sortMode,
                  pinnedCardIds: columnPrefs.pinnedCardIds,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
