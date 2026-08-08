import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../common/app_snack_bar.dart';
import '../controllers/board_controller.dart';
import '../features/app_update/app_update_screen.dart';
import '../features/kanban/card_detail_sheet.dart';
import '../features/project/board_background_layer.dart';
import '../features/project/project_switcher.dart';
import '../features/quick_capture/quick_capture.dart';
import '../features/sync_conflict/conflict_center_screen.dart';
import '../features/trash/trash_screen.dart';
import '../features/views/filter_sheet.dart';
import '../features/views/views.dart';
import '../features/kanban/board_horizontal_scroll.dart';
import '../features/kanban/swimlane.dart';
import '../features/kanban/swimlane_board.dart';
import '../main.dart';
import '../webdav_sync/webdav_sync_service.dart';
import 'settings_screen.dart';
import '../widgets/kanban_column_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FilterSpec _filter = const FilterSpec();

  @override
  void initState() {
    super.initState();
    final controller = context.read<BoardController>();
    controller.syncStatusStream.listen((status) {
      if (!mounted) return;
      setState(() {});
      final syncError = controller.syncError;
      final attachmentWarning = controller.attachmentSyncWarning;
      if (status == SyncStatus.error && syncError != null) {
        showAppSnackBar(context, message: '同步失败：$syncError');
      } else if (status == SyncStatus.success && attachmentWarning != null) {
        showAppSnackBar(context, message: attachmentWarning);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(maybePromptAppUpdate(context));
    });
  }

  Future<void> _quickCapture() async {
    final draft = await showQuickCaptureDialog(context);
    if (!mounted || draft == null) return;
    final id = await context.read<BoardController>().quickCapture(draft);
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: id == null ? '添加失败，请检查目标列' : '已添加「${draft.title}」',
      action: id == null
          ? null
          : SnackBarAction(
              label: '撤销',
              onPressed: () =>
                  context.read<BoardController>().undoLastAction(),
            ),
    );
  }

  Future<void> _undoWithFeedback() async {
    final controller = context.read<BoardController>();
    final label = controller.undoLabel;
    final undone = await controller.undoLastAction();
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: undone
          ? label == null
              ? '已撤销上一项操作'
              : '已撤销：$label'
          : '没有可撤销的操作',
    );
  }

  Future<void> _redoWithFeedback() async {
    final controller = context.read<BoardController>();
    final label = controller.redoLabel;
    final redone = await controller.redoLastAction();
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: redone
          ? label == null
              ? '已重做上一项操作'
              : '已重做：$label'
          : '没有可重做的操作',
    );
  }

  void _requestSync() {
    final controller = context.read<BoardController>();
    if (controller.syncStatus == SyncStatus.syncing) {
      showAppSnackBar(context, message: '正在同步…可点取消按钮');
      return;
    }
    controller.syncNow();
  }

  void _cancelSync() {
    final controller = context.read<BoardController>();
    final cancelled = controller.cancelSync();
    if (!cancelled || !mounted) return;
    showAppSnackBar(context, message: '已取消同步');
  }

  Future<void> _showFilters() async {
    final controller = context.read<BoardController>();
    final labels = {
      for (final label in controller.appSettings.customLabels)
        label.key: label.name,
    };
    final picked = await showCardFilterSheet(
      context: context,
      initial: _filter,
      labels: labels,
    );
    if (picked != null && mounted) setState(() => _filter = picked);
  }

  Future<void> _saveCurrentView() async {
    var draftName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存当前视图'),
        content: TextFormField(
          autofocus: true,
          decoration: const InputDecoration(labelText: '视图名称'),
          onChanged: (value) => draftName = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draftName.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await context.read<BoardController>().saveView(
          name: name,
          filter: _filter,
        );
    if (!mounted) return;
    showAppSnackBar(context, message: '已保存视图「$name」');
  }

  Future<void> _openToday() async {
    final controller = context.read<BoardController>();
    final cards = await controller.loadAllCardReferences();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TodayViewScreen(
          cards: cards,
          onOpen: (reference) => _openReference(reference),
          onToggleCompleted: (reference) =>
              _toggleReferenceCompleted(reference),
        ),
      ),
    );
  }

  Future<void> _openCalendar() async {
    final controller = context.read<BoardController>();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CalendarViewScreen(
          loadCards: controller.loadAllCardReferences,
          onOpen: _openReference,
          onToggleCompleted: _toggleReferenceCompleted,
          onChangeDueDate: (reference, day) async {
            if (controller.activeProjectId != reference.projectId) {
              await controller.switchProject(reference.projectId);
            }
            final endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59);
            await controller.updateCardFull(
              reference.columnId,
              reference.cardId,
              dueDate: endOfDay.millisecondsSinceEpoch,
            );
          },
          onCreateForDay: (day) async {
            final titleController = TextEditingController();
            final title = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('新建当天任务'),
                content: TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '标题'),
                  onSubmitted: (_) =>
                      Navigator.pop(ctx, titleController.text.trim()),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, titleController.text.trim()),
                    child: const Text('创建'),
                  ),
                ],
              ),
            );
            titleController.dispose();
            if (title == null || title.isEmpty || !mounted) return;
            final board = controller.board;
            if (board == null || board.columns.isEmpty) return;
            final columnId = board.columns.first.id;
            final endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59);
            await controller.addCard(
              columnId,
              title,
              dueDate: endOfDay.millisecondsSinceEpoch,
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickSwimlaneMode() async {
    final controller = context.read<BoardController>();
    final current = controller.projectSettings.swimlaneMode;
    final picked = await showModalBottomSheet<SwimlaneMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '看板泳道',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final mode in SwimlaneMode.values)
              ListTile(
                leading: Icon(
                  current == mode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(mode.label),
                onTap: () => Navigator.pop(ctx, mode),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    await controller.saveProjectSettings(
      controller.projectSettings.copyWith(swimlaneMode: picked),
    );
  }

  Future<void> _openSearch() async {
    final controller = context.read<BoardController>();
    final labels = {
      for (final label in controller.appSettings.customLabels)
        label.key: label.name,
    };
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GlobalQueryScreen(
          loadCards: controller.loadAllCardReferences,
          onOpen: _openReference,
          onToggleCompleted: _toggleReferenceCompleted,
          labels: labels,
          savedViews: () => controller.savedViews,
          onSaveView: (id, name, filter) => controller.saveView(
            id: id,
            name: name,
            filter: filter,
          ),
          onDeleteView: (view) => controller.deleteSavedView(view.id),
        ),
      ),
    );
  }

  Future<void> _manageSavedViews() async {
    final controller = context.read<BoardController>();
    final selected = await Navigator.of(context).push<SavedView>(
      MaterialPageRoute<SavedView>(
        builder: (_) => SavedViewsScreen(
          views: controller.savedViews,
          onRename: (view, name) => controller.saveView(
            id: view.id,
            name: name,
            filter: view.filter,
          ),
          onDelete: (view) => controller.deleteSavedView(view.id),
        ),
      ),
    );
    if (selected != null && mounted) _applySavedView(selected);
  }

  void _applySavedView(SavedView view) {
    setState(() => _filter = view.filter);
    showAppSnackBar(
      context,
      message: view.isShowAll ? '已显示全部卡片' : '已应用「${view.name}」',
      clearExisting: true,
    );
  }

  void _showAllCards() {
    _applySavedView(SavedView.showAll);
  }

  Future<void> _openReference(CardReference reference) async {
    final controller = context.read<BoardController>();
    if (controller.activeProjectId != reference.projectId) {
      await controller.switchProject(reference.projectId);
    }
    if (!mounted) return;
    final card = controller.board?.columns
        .where((column) => column.id == reference.columnId)
        .expand((column) => column.cards)
        .where((card) => card.id == reference.cardId)
        .firstOrNull;
    if (card == null) {
      showAppSnackBar(context, message: '这张卡片已被删除或移动，请刷新后重试');
      return;
    }
    await showCardDetailSheet(
      context: context,
      columnId: reference.columnId,
      card: card,
    );
  }

  Future<void> _toggleReferenceCompleted(CardReference reference) async {
    final controller = context.read<BoardController>();
    if (controller.activeProjectId != reference.projectId) {
      await controller.switchProject(reference.projectId);
    }
    await controller.toggleCardCompleted(reference.columnId, reference.cardId);
  }

  void _openTrash() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TrashScreen()),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  void _handleCompactAction(String action) {
    switch (action) {
      case 'today':
        _openToday();
        break;
      case 'calendar':
        _openCalendar();
        break;
      case 'swimlane':
        _pickSwimlaneMode();
        break;
      case 'filter':
        _showFilters();
        break;
      case 'showAll':
        _showAllCards();
        break;
      case 'save':
        _saveCurrentView();
        break;
      case 'saved':
        _manageSavedViews();
        break;
      case 'undo':
        _undoWithFeedback();
        break;
      case 'redo':
        _redoWithFeedback();
        break;
      case 'column':
        _addColumn(context);
        break;
      case 'trash':
        _openTrash();
        break;
      case 'settings':
        _openSettings();
        break;
    }
  }

  Future<void> _addColumn(BuildContext context) async {
    final controller = context.read<BoardController>();
    var draftTitle = '';
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建列'),
        content: TextFormField(
          autofocus: true,
          decoration: const InputDecoration(hintText: '列名称'),
          onChanged: (value) => draftTitle = value,
          onFieldSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, draftTitle.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) {
      final error = await controller.addColumn(title);
      if (error != null && context.mounted) {
        showAppSnackBar(context, message: error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BoardController>();
    final savedViews = controller.savedViews;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _quickCapture,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _undoWithFeedback,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redoWithFeedback,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _redoWithFeedback,
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): () => _requestSync(),
      },
      child: Scaffold(
        backgroundColor: controller.projectSettings.hasBackgroundImage
            ? Colors.transparent
            : null,
        appBar: AppBar(
          title: const ProjectSwitcher(),
          actions: [
            if (!compact)
              IconButton(
                tooltip: controller.canUndo
                    ? '撤销：${controller.undoLabel ?? '上一项操作'}'
                    : '没有可撤销的操作',
                icon: const Icon(Icons.undo),
                onPressed: controller.canUndo ? _undoWithFeedback : null,
              ),
            if (!compact)
              IconButton(
                tooltip: controller.canRedo
                    ? '重做：${controller.redoLabel ?? '上一项操作'}'
                    : '没有可重做的操作',
                icon: const Icon(Icons.redo),
                onPressed: controller.canRedo ? _redoWithFeedback : null,
              ),
            if (!compact)
              IconButton(
                tooltip: '新建列',
                icon: const Icon(Icons.add),
                onPressed: () => _addColumn(context),
              ),
            if (!compact)
              IconButton(
                tooltip: '今日任务',
                icon: const Icon(Icons.today_outlined),
                onPressed: _openToday,
              ),
            if (!compact)
              IconButton(
                tooltip: '日历',
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: _openCalendar,
              ),
            if (!compact)
              IconButton(
                tooltip:
                    '泳道：${controller.projectSettings.swimlaneMode.label}',
                icon: Icon(
                  controller.projectSettings.swimlaneMode == SwimlaneMode.none
                      ? Icons.view_agenda_outlined
                      : Icons.view_agenda,
                ),
                onPressed: _pickSwimlaneMode,
              ),
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: _openSearch,
            ),
            if (!compact)
              PopupMenuButton<String>(
                tooltip: _filter.hasFilters ? '筛选已启用' : '筛选与保存视图',
                icon: Badge(
                  isLabelVisible: _filter.hasFilters,
                  child: const Icon(Icons.filter_list),
                ),
                onSelected: (value) {
                  if (value == '__filter') {
                    _showFilters();
                  } else if (value == '__show_all') {
                    _showAllCards();
                  } else if (value == '__save') {
                    _saveCurrentView();
                  } else if (value == '__manage') {
                    _manageSavedViews();
                  } else {
                    final view = savedViews
                        .where((item) => item.id == value)
                        .firstOrNull;
                    if (view != null) _applySavedView(view);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: '__filter',
                    child: ListTile(
                      leading: Icon(Icons.tune),
                      title: Text('编辑筛选'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: '__show_all',
                    child: ListTile(
                      leading: Icon(Icons.filter_alt_off_outlined),
                      title: Text('显示全部'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: '__save',
                    child: ListTile(
                      leading: Icon(Icons.bookmark_add_outlined),
                      title: Text('保存当前视图'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: '__manage',
                    child: ListTile(
                      leading: Icon(Icons.bookmarks_outlined),
                      title: Text('管理保存视图'),
                    ),
                  ),
                  for (final view in savedViews)
                    PopupMenuItem(
                      value: view.id,
                      child: ListTile(
                        leading: const Icon(Icons.bookmark_outline),
                        title: Text(view.name),
                      ),
                    ),
                ],
              ),
            if (!compact)
              Selector<BoardController, int>(
                selector: (_, c) => c.trashItemCount,
                builder: (context, count, _) => IconButton(
                  tooltip: '回收站',
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: const Icon(Icons.delete_outline),
                  ),
                  onPressed: _openTrash,
                ),
              ),
            Selector<
                BoardController,
                (SyncStatus, String?, int, DateTime?, SyncProgress?)>(
              selector: (_, c) => (
                c.syncStatus,
                c.syncError,
                c.unresolvedConflictCount,
                c.lastSyncedAt,
                c.syncProgress,
              ),
              builder: (context, data, _) => _SyncIndicator(
                status: data.$1,
                error: data.$2,
                conflictCount: data.$3,
                lastSyncedAt: data.$4,
                progress: data.$5,
                compact: compact,
                onTap: () {
                  if (data.$3 <= 0) {
                    _requestSync();
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ConflictCenterScreen(),
                    ),
                  );
                },
                onCancel:
                    data.$1 == SyncStatus.syncing ? _cancelSync : null,
              ),
            ),
            if (!compact)
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
              ),
            if (compact)
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: _handleCompactAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'today',
                    child: ListTile(
                      leading: Icon(Icons.today_outlined),
                      title: Text('今日任务'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'calendar',
                    child: ListTile(
                      leading: Icon(Icons.calendar_month_outlined),
                      title: Text('日历'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'swimlane',
                    child: ListTile(
                      leading: const Icon(Icons.view_agenda_outlined),
                      title: Text(
                        '泳道：${controller.projectSettings.swimlaneMode.label}',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'filter',
                    child: ListTile(
                      leading: Badge(
                        isLabelVisible: _filter.hasFilters,
                        child: const Icon(Icons.filter_list),
                      ),
                      title: const Text('编辑筛选'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'showAll',
                    child: ListTile(
                      leading: Icon(Icons.filter_alt_off_outlined),
                      title: Text('显示全部'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'save',
                    child: ListTile(
                      leading: Icon(Icons.bookmark_add_outlined),
                      title: Text('保存当前视图'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'saved',
                    child: ListTile(
                      leading: Icon(Icons.bookmarks_outlined),
                      title: Text('管理保存视图'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'undo',
                    enabled: controller.canUndo,
                    child: ListTile(
                      leading: const Icon(Icons.undo),
                      title: Text(
                        controller.canUndo
                            ? '撤销：${controller.undoLabel ?? '上一项操作'}'
                            : '没有可撤销的操作',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'redo',
                    enabled: controller.canRedo,
                    child: ListTile(
                      leading: const Icon(Icons.redo),
                      title: Text(
                        controller.canRedo
                            ? '重做：${controller.redoLabel ?? '上一项操作'}'
                            : '没有可重做的操作',
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'column',
                    child: ListTile(
                      leading: Icon(Icons.add),
                      title: Text('新建列'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'trash',
                    child: ListTile(
                      leading: Badge(
                        isLabelVisible: controller.trashItemCount > 0,
                        label: Text('${controller.trashItemCount}'),
                        child: const Icon(Icons.delete_outline),
                      ),
                      title: const Text('回收站'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      leading: Icon(Icons.settings_outlined),
                      title: Text('设置'),
                    ),
                  ),
                ],
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _quickCapture,
          icon: const Icon(Icons.add),
          label: const Text('快速添加'),
        ),
        body: _buildBoardBody(
          compact: compact,
          backgroundAttachmentId:
              controller.projectSettings.backgroundAttachmentId,
          overlayOpacity: controller.projectSettings.backgroundOverlayOpacity,
        ),
      ),
    );
  }

  Widget _buildBoardBody({
    required bool compact,
    required String backgroundAttachmentId,
    required double overlayOpacity,
  }) {
    final content = Consumer<BoardController>(
      builder: (context, controller, _) {
        if (controller.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final board = controller.board;
        if (board == null) {
          return Center(child: Text(controller.errorMessage ?? '加载失败'));
        }

        if (board.columns.isEmpty) {
          return _EmptyBoardState(onCreateColumn: () => _addColumn(context));
        }

        final projectId = controller.activeProjectId ?? board.id;
        final spec = _filter;
        final references = buildCardReferences(
          manifest: controller.manifest!,
          boards: {projectId: board},
          customLabels: controller.appSettings.customLabels,
        );
        final visibleIds = const CardQueryService()
            .query(references, spec)
            .map((card) => card.cardId)
            .toSet();
        if (spec.hasFilters && visibleIds.isEmpty) {
          return _SearchEmptyState(
            onClear: () {
              setState(() => _filter = const FilterSpec());
            },
          );
        }

        if (compact) {
          if (controller.projectSettings.swimlaneMode != SwimlaneMode.none) {
            return SwimlaneBoard(
              board: board,
              visibleCardIds: visibleIds,
              mode: controller.projectSettings.swimlaneMode,
              compact: true,
            );
          }
          final width = MediaQuery.sizeOf(context).width - 24;
          return PageView.builder(
            padEnds: false,
            controller: PageController(viewportFraction: 0.94),
            itemCount: board.columns.length,
            itemBuilder: (context, index) {
              final column = board.columns[index];
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 0, 88),
                child: KanbanColumnWidget(
                  column: column,
                  columnIndex: index,
                  visibleCardIds: visibleIds,
                  width: width,
                ),
              );
            },
          );
        }

        if (controller.projectSettings.swimlaneMode != SwimlaneMode.none) {
          return SwimlaneBoard(
            board: board,
            visibleCardIds: visibleIds,
            mode: controller.projectSettings.swimlaneMode,
          );
        }

        return BoardHorizontalScroll(
          builder: (context, scrollController) {
            return ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              scrollController: scrollController,
              padding: const EdgeInsets.all(16),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final t = Curves.easeInOut.transform(animation.value);
                    return Material(
                      elevation: 8 * t,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              itemCount: board.columns.length,
              onReorderItem: (oldIndex, adjustedNewIndex) {
                final legacyNewIndex = adjustedNewIndex > oldIndex
                    ? adjustedNewIndex + 1
                    : adjustedNewIndex;
                controller.reorderColumn(oldIndex, legacyNewIndex);
              },
              itemBuilder: (context, index) {
                final column = board.columns[index];
                return Padding(
                  key: ValueKey(column.id),
                  padding: EdgeInsets.only(
                    right: index < board.columns.length - 1 ? 12 : 0,
                  ),
                  child: KanbanColumnWidget(
                    column: column,
                    columnIndex: index,
                    visibleCardIds: visibleIds,
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (backgroundAttachmentId.isEmpty) return content;

    return Stack(
      fit: StackFit.expand,
      children: [
        BoardBackgroundLayer(
          attachmentId: backgroundAttachmentId,
          overlayOpacity: overlayOpacity,
        ),
        content,
      ],
    );
  }
}

class _EmptyBoardState extends StatelessWidget {
  const _EmptyBoardState({required this.onCreateColumn});

  final VoidCallback onCreateColumn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.view_column_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '先创建第一列',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '创建列后，就可以用右下角的“快速添加”录入卡片',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreateColumn,
              icon: const Icon(Icons.add),
              label: const Text('创建第一列'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: '没有符合条件的卡片',
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 52,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text('没有符合条件的卡片', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onClear,
                child: const Text('清除搜索和筛选'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({
    required this.status,
    required this.onTap,
    this.onCancel,
    this.error,
    this.conflictCount = 0,
    this.lastSyncedAt,
    this.progress,
    this.compact = false,
  });

  final SyncStatus status;
  final String? error;
  final int conflictCount;
  final DateTime? lastSyncedAt;
  final SyncProgress? progress;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = conflictCount > 0
        ? colorScheme.error
        : switch (status) {
            SyncStatus.error => colorScheme.error,
            SyncStatus.success => colorScheme.tertiary,
            SyncStatus.syncing => colorScheme.primary,
            SyncStatus.idle => null,
          };

    final syncing = status == SyncStatus.syncing;
    final label = conflictCount > 0
        ? '有 $conflictCount 处冲突'
        : syncStatusWithLastSuccessLabel(
            status,
            lastSyncedAt,
            progress: progress,
          );

    final lastSuccess = lastSyncedAt == null
        ? '尚未成功同步'
        : '上次成功同步：${formatSyncTime(lastSyncedAt!)}';

    final progressDetail = progress == null
        ? null
        : [
            progress!.phaseLabel,
            if (progress!.hasTotal) '${progress!.completed}/${progress!.total}',
            if (progress!.skipped > 0) '跳过 ${progress!.skipped} 个未变更文件',
            if (progress!.currentLabel != null) progress!.currentLabel!,
          ].join(' · ');

    final tooltip = conflictCount > 0
        ? '有未解决的同步冲突，点击进入冲突中心'
        : syncing
            ? (progressDetail == null
                ? '正在同步…可点击取消'
                : '$progressDetail\n可点击取消')
            : error == null
                ? '$lastSuccess\n点击立即同步'
                : '$error\n$lastSuccess';
    final icon = Icon(
      conflictCount > 0 ? Icons.warning_amber_outlined : syncStatusIcon(status),
      color: color,
      size: 20,
    );

    final syncButton = compact
        ? IconButton(
            onPressed: onTap,
            icon: Badge(
              isLabelVisible: conflictCount > 0,
              label: Text('$conflictCount'),
              child: icon,
            ),
          )
        : TextButton.icon(
            onPressed: onTap,
            icon: icon,
            label: Text(
              label,
              style: TextStyle(color: color, fontSize: 13),
            ),
          );

    final cancelButton = onCancel == null
        ? null
        : IconButton(
            tooltip: '取消同步',
            onPressed: onCancel,
            icon: Icon(
              Icons.close,
              color: colorScheme.onSurfaceVariant,
              size: 20,
            ),
          );

    return Semantics(
      liveRegion: true,
      label: syncing ? '$label，可取消' : label,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: cancelButton == null
            ? syncButton
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  syncButton,
                  cancelButton,
                ],
              ),
      ),
    );
  }
}
