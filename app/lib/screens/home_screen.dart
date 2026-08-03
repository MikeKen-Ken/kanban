import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/board_controller.dart';
import '../features/kanban/card_detail_sheet.dart';
import '../features/project/project_switcher.dart';
import '../features/quick_capture/quick_capture.dart';
import '../features/sync_conflict/conflict_center_screen.dart';
import '../features/trash/trash_screen.dart';
import '../features/views/filter_sheet.dart';
import '../features/views/today_view_screen.dart';
import '../features/views/views.dart';
import '../main.dart';
import '../utils/ime_guard.dart';
import '../webdav_sync/webdav_sync_service.dart';
import 'settings_screen.dart';
import '../widgets/kanban_column_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with ImeGuard {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _showSearch = false;
  FilterSpec _filter = const FilterSpec();

  Iterable<TextEditingController> get _textControllers => [_searchController];

  @override
  void initState() {
    super.initState();
    final controller = context.read<BoardController>();
    controller.syncStatusStream.listen((status) {
      if (!mounted) return;
      deferRebuildIfComposing(_textControllers);
      final syncError = controller.syncError;
      final attachmentWarning = controller.attachmentSyncWarning;
      if (status == SyncStatus.error && syncError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败：$syncError')),
        );
      } else if (status == SyncStatus.success && attachmentWarning != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(attachmentWarning)),
        );
      }
    });
    bindImeGuard(_textControllers);
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (isComposing(_searchController)) return;
    final v = _searchController.text;
    if (v != _searchQuery) {
      setState(() => _searchQuery = v);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _showAndFocusSearch() {
    setState(() => _showSearch = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  Future<void> _quickCapture() async {
    final draft = await showQuickCaptureDialog(context);
    if (!mounted || draft == null) return;
    final id = await context.read<BoardController>().quickCapture(draft);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(id == null ? '添加失败，请检查目标列' : '已添加「${draft.title}」'),
        action: id == null
            ? null
            : SnackBarAction(
                label: '撤销',
                onPressed: () =>
                    context.read<BoardController>().undoLastAction(),
              ),
      ),
    );
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
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存当前视图'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: '视图名称'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    await context.read<BoardController>().saveView(
          name: name,
          filter: _filter.copyWith(keyword: _searchQuery),
        );
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
    if (card == null) return;
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

  Future<void> _addColumn(BuildContext context) async {
    final controller = context.read<BoardController>();
    final textController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建列'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '列名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) {
      await controller.addColumn(title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedViews = context.watch<BoardController>().savedViews;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _showAndFocusSearch,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _quickCapture,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            context.read<BoardController>().undoLastAction(),
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): () => context.read<BoardController>().syncNow(),
      },
      child: Scaffold(
        appBar: AppBar(
          title: const ProjectSwitcher(),
          actions: [
            IconButton(
              tooltip: '新建列',
              icon: const Icon(Icons.view_column_outlined),
              onPressed: () => _addColumn(context),
            ),
            IconButton(
              tooltip: '今日任务',
              icon: const Icon(Icons.today_outlined),
              onPressed: _openToday,
            ),
            PopupMenuButton<String>(
              tooltip: _filter.hasFilters ? '筛选已启用' : '筛选与保存视图',
              icon: Badge(
                isLabelVisible: _filter.hasFilters,
                child: const Icon(Icons.filter_list),
              ),
              onSelected: (value) {
                if (value == '__filter') {
                  _showFilters();
                } else if (value == '__save') {
                  _saveCurrentView();
                } else {
                  final view =
                      savedViews.where((item) => item.id == value).firstOrNull;
                  if (view == null) return;
                  _searchController.text = view.filter.keyword;
                  setState(() {
                    _searchQuery = view.filter.keyword;
                    _filter = view.filter.copyWith(keyword: '');
                  });
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
                  value: '__save',
                  child: ListTile(
                    leading: Icon(Icons.bookmark_add_outlined),
                    title: Text('保存当前视图'),
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
            IconButton(
              tooltip: _showSearch ? '关闭搜索' : '搜索卡片',
              icon: Icon(
                _showSearch ? Icons.search_off : Icons.search,
              ),
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchController.clear();
                    _searchQuery = '';
                  }
                });
                if (_showSearch) _showAndFocusSearch();
              },
            ),
            Selector<BoardController, int>(
              selector: (_, c) => c.trashItemCount,
              builder: (context, count, _) => IconButton(
                tooltip: '回收站',
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(Icons.delete_outline),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TrashScreen(),
                    ),
                  );
                },
              ),
            ),
            Selector<BoardController, (SyncStatus, String?, int, DateTime?)>(
              selector: (_, c) => (
                c.syncStatus,
                c.syncError,
                c.unresolvedConflictCount,
                c.lastSyncedAt,
              ),
              builder: (context, data, _) => _SyncIndicator(
                status: data.$1,
                error: data.$2,
                conflictCount: data.$3,
                lastSyncedAt: data.$4,
                onTap: () {
                  final controller = context.read<BoardController>();
                  if (data.$3 <= 0) {
                    controller.syncNow();
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ConflictCenterScreen(),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ],
          bottom: _showSearch
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      key: const ValueKey('home-search'),
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: '搜索标题、备注、标签、子任务…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                )
              : null,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _quickCapture,
          icon: const Icon(Icons.add),
          label: const Text('快速添加'),
        ),
        body: Consumer<BoardController>(
          builder: (context, controller, _) {
            if (controller.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final board = controller.board;
            if (board == null) {
              return Center(child: Text(controller.errorMessage ?? '加载失败'));
            }

            if (board.columns.isEmpty) {
              return const Center(child: Text('点击右下角添加第一列'));
            }

            final projectId = controller.activeProjectId ?? board.id;
            final spec = _filter.copyWith(keyword: _searchQuery);
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
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _filter = const FilterSpec();
                  });
                },
              );
            }

            final compact = MediaQuery.sizeOf(context).width < 600;
            if (compact) {
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

            return Scrollbar(
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
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
              ),
            );
          },
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
    this.error,
    this.conflictCount = 0,
    this.lastSyncedAt,
  });

  final SyncStatus status;
  final String? error;
  final int conflictCount;
  final DateTime? lastSyncedAt;
  final VoidCallback onTap;

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

    final label = conflictCount > 0
        ? '有 $conflictCount 处冲突'
        : syncStatusWithLastSuccessLabel(status, lastSyncedAt);

    final lastSuccess = lastSyncedAt == null
        ? '尚未成功同步'
        : '上次成功同步：${formatSyncTime(lastSyncedAt!)}';

    return Semantics(
      liveRegion: true,
      label: label,
      button: true,
      child: Tooltip(
        message: conflictCount > 0
            ? '有未解决的同步冲突，点击进入冲突中心'
            : error == null
                ? '$lastSuccess\n点击立即同步'
                : '$error\n$lastSuccess',
        child: TextButton.icon(
          onPressed: onTap,
          icon: Icon(
            conflictCount > 0
                ? Icons.warning_amber_outlined
                : syncStatusIcon(status),
            color: color,
            size: 20,
          ),
          label: Text(
            label,
            style: TextStyle(color: color, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
