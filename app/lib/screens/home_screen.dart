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
import '../features/views/views.dart';
import '../features/wallpapers/wallpaper_models.dart';
import '../features/kanban/board_horizontal_scroll.dart';
import '../features/kanban/swimlane.dart';
import '../features/kanban/swimlane_board.dart';
import '../features/remote_actions/remote_actions_toolbar_button.dart';
import '../models/kanban_models.dart';
import '../webdav_sync/sync_actions_sheet.dart';
import '../webdav_sync/sync_actions_switcher.dart';
import '../webdav_sync/webdav_sync_service.dart';
import 'settings_screen.dart';
import '../widgets/kanban_column_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<SyncStatus>? _syncStatusSubscription;

  @override
  void initState() {
    super.initState();
    final controller = context.read<BoardController>();
    _syncStatusSubscription = controller.syncStatusStream.listen((status) {
      if (!mounted) return;
      final syncError = controller.syncError;
      final attachmentWarning = controller.attachmentSyncWarning;
      if (status == SyncStatus.error && syncError != null) {
        showAppSnackBar(context, message: 'Sync failed: $syncError');
      } else if (status == SyncStatus.success && attachmentWarning != null) {
        showAppSnackBar(context, message: attachmentWarning);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(maybePromptAppUpdate(context));
    });
  }

  @override
  void dispose() {
    _syncStatusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _quickCapture() async {
    final draft = await showQuickCaptureDialog(context);
    if (!mounted || draft == null) return;
    final id = await context.read<BoardController>().quickCapture(draft);
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: id == null
          ? 'Failed to add; check the target column'
          : 'Added "${draft.title}"',
      action: id == null
          ? null
          : SnackBarAction(
              label: 'Undo',
              onPressed: () => context.read<BoardController>().undoLastAction(),
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
              ? 'Undid the previous action'
              : 'Undid: $label'
          : 'There is nothing to undo',
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
              ? 'Redid the previous action'
              : 'Redid: $label'
          : 'There is nothing to redo',
    );
  }

  void _requestSync() {
    unawaited(showSyncActionsAndRun(context, context.read<BoardController>()));
  }

  void _cancelSync() {
    final controller = context.read<BoardController>();
    final cancelled = controller.cancelSync();
    if (!cancelled || !mounted) return;
    showAppSnackBar(context, message: 'Sync canceled');
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
                title: const Text('Create task for this day'),
                content: TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title'),
                  onSubmitted: (_) =>
                      Navigator.pop(ctx, titleController.text.trim()),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, titleController.text.trim()),
                    child: const Text('Create'),
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

  Future<void> _cycleSwimlaneMode() async {
    final controller = context.read<BoardController>();
    final current = controller.projectSettings.swimlaneMode;
    final next = nextSwimlaneMode(current);
    await controller.saveProjectSettings(
      controller.projectSettings.copyWith(swimlaneMode: next),
    );
    if (!mounted) return;
    showAppSnackBar(context, message: 'Swimlane: ${next.label}');
  }

  Future<void> _openSearch() async {
    final controller = context.read<BoardController>();
    final currentProjectId = controller.uiActiveProjectId;
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
          initialFilter: currentProjectId == null
              ? const FilterSpec()
              : FilterSpec(projectIds: [currentProjectId]),
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
    if (card == null) {
      showAppSnackBar(context,
          message: 'This card was deleted or moved. Refresh and try again');
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
    final error = await controller.toggleCardCompleted(
      reference.columnId,
      reference.cardId,
    );
    if (error != null && mounted) {
      showAppSnackBar(context, message: error);
    }
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
      case 'calendar':
        _openCalendar();
        break;
      case 'swimlane':
        _cycleSwimlaneMode();
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
      case 'search':
        _openSearch();
        break;
    }
  }

  Future<void> _addColumn(BuildContext context) async {
    final controller = context.read<BoardController>();
    var draftTitle = '';
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create column'),
        content: TextFormField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Column name'),
          onChanged: (value) => draftTitle = value,
          onFieldSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, draftTitle.trim()),
            child: const Text('Create'),
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
    final chrome = context.select<
        BoardController,
        ({
          bool hasBackground,
          bool canUndo,
          String? undoLabel,
          bool canRedo,
          String? redoLabel,
          SwimlaneMode swimlaneMode,
          List<String> wallpaperIds,
          String activeWallpaperId,
          WallpaperPlaybackMode wallpaperPlaybackMode,
          int wallpaperIntervalSeconds,
          double overlayOpacity,
        })>(
      (value) => (
        hasBackground: value.hasDisplayableBackground,
        canUndo: value.canUndo,
        undoLabel: value.undoLabel,
        canRedo: value.canRedo,
        redoLabel: value.redoLabel,
        swimlaneMode: value.projectSettings.swimlaneMode,
        wallpaperIds: value.displayableWallpaperIds,
        activeWallpaperId: value.projectSettings.wallpaperActiveId,
        wallpaperPlaybackMode: value.projectSettings.wallpaperPlaybackMode,
        wallpaperIntervalSeconds:
            value.projectSettings.wallpaperIntervalSeconds,
        overlayOpacity: value.projectSettings.backgroundOverlayOpacity,
      ),
    );
    final compact = MediaQuery.sizeOf(context).width < 600;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _quickCapture,
        const SingleActivator(LogicalKeyboardKey.keyI, control: true):
            _openSettings,
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
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: chrome.hasBackground ? Colors.transparent : null,
          appBar: AppBar(
            title: const ProjectSwitcher(),
            actions: [
              if (!compact)
                IconButton(
                  tooltip: chrome.canUndo
                      ? 'Undo: ${chrome.undoLabel ?? 'previous action'}'
                      : 'There is nothing to undo',
                  icon: const Icon(Icons.undo),
                  onPressed: chrome.canUndo ? _undoWithFeedback : null,
                ),
              if (!compact)
                IconButton(
                  tooltip: chrome.canRedo
                      ? 'Redo: ${chrome.redoLabel ?? 'previous action'}'
                      : 'There is nothing to redo',
                  icon: const Icon(Icons.redo),
                  onPressed: chrome.canRedo ? _redoWithFeedback : null,
                ),
              if (!compact)
                IconButton(
                  tooltip: 'Create column',
                  icon: const Icon(Icons.add),
                  onPressed: () => _addColumn(context),
                ),
              if (!compact)
                IconButton(
                  tooltip: 'Calendar',
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: _openCalendar,
                ),
              if (!compact)
                IconButton(
                  tooltip: 'Swimlane: ${chrome.swimlaneMode.label}',
                  icon: Icon(
                    chrome.swimlaneMode == SwimlaneMode.none
                        ? Icons.view_agenda_outlined
                        : Icons.view_agenda,
                  ),
                  onPressed: _cycleSwimlaneMode,
                ),
              if (!compact)
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search),
                  onPressed: _openSearch,
                ),
              if (!compact)
                IconButton(
                  tooltip: 'Trash',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _openTrash,
                ),
              if (!compact) const RemoteActionsToolbarButton(),
              Selector<BoardController,
                  (SyncStatus, String?, int, DateTime?, SyncProgress?, int)>(
                selector: (_, c) => (
                  c.syncStatus,
                  c.syncError,
                  c.unresolvedConflictCount,
                  c.lastSyncedAt,
                  c.syncProgress,
                  c.pendingSyncUploadCount,
                ),
                builder: (context, data, _) => SyncActionsSwitcher(
                  status: data.$1,
                  error: data.$2,
                  conflictCount: data.$3,
                  lastSyncedAt: data.$4,
                  progress: data.$5,
                  pendingUploadCount: data.$6,
                  compact: compact,
                  onConflictTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ConflictCenterScreen(),
                      ),
                    );
                  },
                  onCancel: data.$1 == SyncStatus.syncing ? _cancelSync : null,
                ),
              ),
              if (!compact)
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _openSettings,
                ),
              if (compact)
                PopupMenuButton<String>(
                  tooltip: 'More actions',
                  onSelected: _handleCompactAction,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'search',
                      child: ListTile(
                        leading: Icon(Icons.search),
                        title: Text('Search'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'calendar',
                      child: ListTile(
                        leading: Icon(Icons.calendar_month_outlined),
                        title: Text('Calendar'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'swimlane',
                      child: ListTile(
                        leading: const Icon(Icons.view_agenda_outlined),
                        title: Text(
                          'Swimlane: ${chrome.swimlaneMode.label}',
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'undo',
                      enabled: chrome.canUndo,
                      child: ListTile(
                        leading: const Icon(Icons.undo),
                        title: Text(
                          chrome.canUndo
                              ? 'Undo: ${chrome.undoLabel ?? 'previous action'}'
                              : 'There is nothing to undo',
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'redo',
                      enabled: chrome.canRedo,
                      child: ListTile(
                        leading: const Icon(Icons.redo),
                        title: Text(
                          chrome.canRedo
                              ? 'Redo: ${chrome.redoLabel ?? 'previous action'}'
                              : 'There is nothing to redo',
                        ),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'column',
                      child: ListTile(
                        leading: Icon(Icons.add),
                        title: Text('Create column'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'trash',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Trash'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'settings',
                      child: ListTile(
                        leading: Icon(Icons.settings_outlined),
                        title: Text('Settings'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _quickCapture,
            icon: const Icon(Icons.add),
            label: const Text('Quick add'),
          ),
          body: _buildBoardBody(
            compact: compact,
            wallpaperIds: chrome.wallpaperIds,
            activeWallpaperId: chrome.activeWallpaperId,
            wallpaperPlaybackMode: chrome.wallpaperPlaybackMode,
            wallpaperIntervalSeconds: chrome.wallpaperIntervalSeconds,
            overlayOpacity: chrome.overlayOpacity,
          ),
        ),
      ),
    );
  }

  Widget _buildBoardBody({
    required bool compact,
    required List<String> wallpaperIds,
    required String activeWallpaperId,
    required WallpaperPlaybackMode wallpaperPlaybackMode,
    required int wallpaperIntervalSeconds,
    required double overlayOpacity,
  }) {
    final content = Selector<
        BoardController,
        ({
          bool isLoading,
          String? errorMessage,
          KanbanBoard? board,
          SwimlaneMode swimlaneMode,
        })>(
      selector: (_, value) => (
        isLoading: value.isLoading,
        errorMessage: value.errorMessage,
        board: value.board,
        swimlaneMode: value.projectSettings.swimlaneMode,
      ),
      builder: (context, selected, _) {
        if (selected.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final controller = context.read<BoardController>();
        final board = selected.board;
        if (board == null) {
          return Center(child: Text(selected.errorMessage ?? 'Load failed'));
        }

        if (board.columns.isEmpty) {
          return _EmptyBoardState(onCreateColumn: () => _addColumn(context));
        }

        final visibleIds = {
          for (final column in board.columns)
            for (final card in column.cards) card.id,
        };

        if (compact) {
          if (selected.swimlaneMode != SwimlaneMode.none) {
            return SwimlaneBoard(
              board: board,
              visibleCardIds: visibleIds,
              mode: selected.swimlaneMode,
              compact: true,
            );
          }
          final width = MediaQuery.sizeOf(context).width - 24;
          return KanbanHorizontalScrollConfiguration(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: board.columns.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final column = board.columns[index];
                return KanbanColumnWidget(
                  column: column,
                  columnIndex: index,
                  visibleCardIds: visibleIds,
                  width: width,
                );
              },
            ),
          );
        }

        if (selected.swimlaneMode != SwimlaneMode.none) {
          return SwimlaneBoard(
            board: board,
            visibleCardIds: visibleIds,
            mode: selected.swimlaneMode,
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

    if (wallpaperIds.isEmpty) return content;

    return Stack(
      fit: StackFit.expand,
      children: [
        BoardBackgroundLayer(
          wallpaperIds: wallpaperIds,
          activeWallpaperId: activeWallpaperId,
          playbackMode: wallpaperPlaybackMode,
          intervalSeconds: wallpaperIntervalSeconds,
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
              'Create your first column',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'After creating a column, use "Quick add" in the lower-right corner to add cards',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreateColumn,
              icon: const Icon(Icons.add),
              label: const Text('Create first column'),
            ),
          ],
        ),
      ),
    );
  }
}
