import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../kanban/next_work_card.dart';
import '../kanban/verify_column.dart';
import '../project/project_list_preferences.dart';
import '../project/projects_manifest.dart';
import 'agent_dispatch_after_queue.dart';
import 'agent_dispatch_after_queue_field.dart';
import 'agent_dispatch_hub_batch.dart';
import 'agent_dispatch_hub_overview.dart';
import 'agent_dispatch_progress.dart';
import 'agent_dispatch_registry.dart';
import 'agent_dispatch_settings.dart';
import 'agent_dispatch_window.dart';

class AgentDispatchHubItem {
  const AgentDispatchHubItem({
    required this.projectId,
    required this.title,
    required this.running,
    this.isCurrent = false,
    this.progressLabel,
    this.progressFraction,
    this.currentTitle,
    this.phaseLabel,
    this.engine,
    this.model,
    this.modelParams = const {},
    this.batchStartedAt,
    this.cardStartedAt,
  });

  final String projectId;
  final String title;
  final bool running;
  final bool isCurrent;
  final String? progressLabel;
  final double? progressFraction;
  final String? currentTitle;
  final String? phaseLabel;
  final String? engine;
  final String? model;
  final Map<String, String> modelParams;
  final DateTime? batchStartedAt;
  final DateTime? cardStartedAt;
}

List<AgentDispatchHubItem> orderAgentDispatchHubItems(
  Iterable<AgentDispatchHubItem> items,
) {
  final running = <AgentDispatchHubItem>[];
  final idle = <AgentDispatchHubItem>[];
  for (final item in items) {
    if (item.running) {
      running.add(item);
    } else {
      idle.add(item);
    }
  }
  return [...running, ...idle];
}

List<ProjectEntry> orderAgentDispatchHubProjects(
  Iterable<ProjectEntry> projects, {
  required ProjectSortMode sortMode,
  required List<String> pinnedProjectIds,
  required Map<String, int> lastUsedAtByProjectId,
}) {
  return sortProjectEntries(
    projects.toList(),
    sortMode: sortMode,
    pinnedProjectIds: pinnedProjectIds,
    lastUsedAtByProjectId: lastUsedAtByProjectId,
  );
}

/// Agent 调度总览：列出各项目是否在跑及进度。
class AgentDispatchHub extends StatelessWidget {
  const AgentDispatchHub({super.key});

  @override
  Widget build(BuildContext context) {
    final board = context.watch<BoardController>();
    return AnimatedBuilder(
      animation: AgentDispatchRegistry.instance,
      builder: (context, _) {
        final registry = AgentDispatchRegistry.instance;
        final currentId = board.uiActiveProjectId ?? board.activeProjectId;
        final currentBoard = board.board;
        final orderedProjects = orderAgentDispatchHubProjects(
          board.manifest?.projects ?? const <ProjectEntry>[],
          sortMode: board.appSettings.projectSortMode,
          pinnedProjectIds: board.appSettings.pinnedProjectIds,
          lastUsedAtByProjectId: board.appSettings.projectLastUsedAt,
        );
        final items = orderAgentDispatchHubItems([
          for (final project in orderedProjects)
            _itemFor(registry, project, currentId, currentBoard),
        ]);
        return AgentDispatchHubView(
          items: items,
          onClose: AgentDispatchWindow.hide,
          onOpenProject: AgentDispatchWindow.openProject,
          onRunProject: (projectId) => _runFromHub(context, board, projectId),
          onStopProject: stopAgentDispatchFromHub,
          afterQueueStatus: _hubAfterQueueStatus(registry),
          afterQueuePane: const AgentDispatchHubAfterQueuePane(),
        );
      },
    );
  }

  String? _hubAfterQueueStatus(AgentDispatchRegistry registry) {
    final hubQueue = registry.hubAfterQueue;
    if (hubQueue.running) return 'Completion queue is running';
    if (hubQueue.pending && registry.anyRunning) {
      return 'Completion queue waits until every running batch finishes';
    }
    return null;
  }

  Future<void> _runFromHub(
    BuildContext context,
    BoardController board,
    String projectId,
  ) async {
    final result = await startAgentDispatchFromHub(
      projectId: projectId,
      board: board,
      confirmSameRepo: (otherProjectId, repo) =>
          _confirmSameRepo(context, board, otherProjectId, repo),
    );
    if (!context.mounted) return;
    final message = result.message?.trim();
    if (message != null && message.isNotEmpty) {
      showAppSnackBar(context, message: message);
    }
  }

  Future<bool> _confirmSameRepo(
    BuildContext context,
    BoardController board,
    String otherProjectId,
    String repo,
  ) async {
    final otherTitle =
        board.manifest?.findById(otherProjectId)?.title ?? otherProjectId;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Repository is used by another project'),
        content: Text(
          'Project "$otherTitle" is already running in this repository:\n$repo\n\n'
          'Running in parallel may modify the same files. Continue anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Run anyway'),
          ),
        ],
      ),
    );
    return go == true;
  }

  AgentDispatchHubItem _itemFor(
    AgentDispatchRegistry registry,
    ProjectEntry project,
    String? currentId,
    KanbanBoard? currentBoard,
  ) {
    var progress = registry.progressOf(project.id);
    if (progress.running &&
        currentBoard != null &&
        currentBoard.id == project.id) {
      final hasActiveCard = hasIncompleteDoingCard(currentBoard);
      progress = applyLiveBoardQueue(
        progress,
        remainingQueue: countRemainingDispatchQueue(
          currentBoard,
          hasActiveCard: hasActiveCard,
        ),
        hasActiveCard: hasActiveCard,
      );
    }
    return AgentDispatchHubItem(
      projectId: project.id,
      title: project.title,
      running: progress.running,
      isCurrent: project.id == currentId,
      progressLabel: progress.running ? progress.liveCardLabel : null,
      progressFraction: progress.fraction,
      currentTitle: progress.currentTitle,
      phaseLabel: progress.phaseLabel,
      engine: progress.engine,
      model: progress.model,
      modelParams: progress.modelParams,
      batchStartedAt: progress.batchStartedAt,
      cardStartedAt: progress.cardStartedAt,
    );
  }
}

class AgentDispatchHubView extends StatefulWidget {
  const AgentDispatchHubView({
    required this.items,
    required this.onClose,
    required this.onOpenProject,
    required this.onRunProject,
    required this.onStopProject,
    this.afterQueuePane,
    this.afterQueueStatus,
    super.key,
  });

  final List<AgentDispatchHubItem> items;
  final VoidCallback onClose;
  final void Function(String projectId) onOpenProject;
  final Future<void> Function(String projectId) onRunProject;
  final Future<void> Function(String projectId) onStopProject;
  final Widget? afterQueuePane;
  final String? afterQueueStatus;

  @override
  State<AgentDispatchHubView> createState() => _AgentDispatchHubViewState();
}

class _AgentDispatchHubViewState extends State<AgentDispatchHubView> {
  Timer? _ticker;
  final _startingIds = <String>{};
  final _stoppingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AgentDispatchHubView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasRunning = oldWidget.items.any((item) => item.running);
    final isRunning = widget.items.any((item) => item.running);
    if (wasRunning != isRunning) _syncTicker();
    _pruneActionIds();
  }

  void _pruneActionIds() {
    final byId = {
      for (final item in widget.items) item.projectId: item.running,
    };
    _startingIds.removeWhere((id) => byId[id] == true || !byId.containsKey(id));
    _stoppingIds.removeWhere((id) => byId[id] != true);
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (!widget.items.any((item) => item.running)) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _handleRun(String projectId) async {
    if (_startingIds.contains(projectId) || _stoppingIds.contains(projectId)) {
      return;
    }
    setState(() => _startingIds.add(projectId));
    try {
      await widget.onRunProject(projectId);
    } finally {
      if (mounted) {
        setState(() => _startingIds.remove(projectId));
      }
    }
  }

  Future<void> _handleStop(String projectId) async {
    if (_stoppingIds.contains(projectId) || _startingIds.contains(projectId)) {
      return;
    }
    setState(() => _stoppingIds.add(projectId));
    try {
      await widget.onStopProject(projectId);
    } finally {
      if (mounted) {
        setState(() => _stoppingIds.remove(projectId));
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = (viewport.width - 96).clamp(480.0, 720.0).toDouble();
    final dialogHeight = (viewport.height - 180).clamp(360.0, 640.0).toDouble();
    final runningCount = widget.items.where((item) => item.running).length;
    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      title: Text(
        runningCount > 0
            ? 'Agent Dispatch overview ($runningCount running)'
            : 'Agent Dispatch overview',
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: widget.items.isEmpty
                  ? const Center(child: Text('No board projects yet'))
                  : ListView.separated(
                      itemCount: widget.items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        return _HubProjectTile(
                          item: item,
                          starting: _startingIds.contains(item.projectId),
                          stopping: _stoppingIds.contains(item.projectId),
                          onOpen: () => widget.onOpenProject(item.projectId),
                          onRun: () => _handleRun(item.projectId),
                          onStop: () => _handleStop(item.projectId),
                        );
                      },
                    ),
            ),
            if (widget.afterQueuePane != null) ...[
              const Divider(height: 24),
              if (widget.afterQueueStatus != null) ...[
                Text(
                  widget.afterQueueStatus!,
                  key: const ValueKey('agent-dispatch-hub-after-queue-status'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
              ],
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: dialogHeight * 0.45),
                child: SingleChildScrollView(child: widget.afterQueuePane),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: widget.onClose, child: const Text('Close')),
      ],
    );
  }
}

class _HubProjectTile extends StatelessWidget {
  const _HubProjectTile({
    required this.item,
    required this.starting,
    required this.stopping,
    required this.onOpen,
    required this.onRun,
    required this.onStop,
  });

  final AgentDispatchHubItem item;
  final bool starting;
  final bool stopping;
  final VoidCallback onOpen;
  final VoidCallback onRun;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overview = item.running
        ? AgentDispatchHubOverview.running(
            liveCardLabel: item.progressLabel ?? '',
            currentTitle: item.currentTitle ?? '',
            phaseLabel: item.phaseLabel ?? '',
            engine: item.engine ?? '',
            model: item.model ?? '',
            modelParams: item.modelParams,
            batchStartedAt: item.batchStartedAt,
            cardStartedAt: item.cardStartedAt,
          )
        : null;
    final status = overview?.statusLine ?? 'Not running';
    final actionsBusy = starting || stopping;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Icon(
        item.running ? Icons.smart_toy : Icons.smart_toy_outlined,
        color: item.running ? theme.colorScheme.primary : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (item.isCurrent)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'Current',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(status),
          if (overview != null) ...[
            const SizedBox(height: 4),
            Text(
              overview.cardTitle,
              key: ValueKey('agent-dispatch-hub-card-${item.projectId}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              overview.engineModelLabel,
              key: ValueKey('agent-dispatch-hub-model-${item.projectId}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (overview.modelDetailLabel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                overview.modelDetailLabel,
                key: ValueKey('agent-dispatch-hub-params-${item.projectId}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (overview.elapsedLabel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                overview.elapsedLabel,
                key: ValueKey('agent-dispatch-hub-elapsed-${item.projectId}'),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
          if (item.running) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: item.progressFraction),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.running)
                OutlinedButton(
                  key: ValueKey('agent-dispatch-hub-stop-${item.projectId}'),
                  onPressed: actionsBusy ? null : onStop,
                  child: Text(stopping ? 'Stopping…' : 'Stop'),
                )
              else
                FilledButton.tonalIcon(
                  key: ValueKey('agent-dispatch-hub-run-${item.projectId}'),
                  onPressed: actionsBusy ? null : onRun,
                  icon: starting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(starting ? 'Starting…' : 'Run'),
                ),
              TextButton(
                onPressed: onOpen,
                child: Text(item.running ? 'View' : 'Open'),
              ),
            ],
          ),
        ],
      ),
      onTap: onOpen,
    );
  }
}

/// 总览上的完成后队列编辑器；与各项目工作台队列分开保存。
class AgentDispatchHubAfterQueuePane extends StatefulWidget {
  const AgentDispatchHubAfterQueuePane({super.key});

  @override
  State<AgentDispatchHubAfterQueuePane> createState() =>
      _AgentDispatchHubAfterQueuePaneState();
}

class _AgentDispatchHubAfterQueuePaneState
    extends State<AgentDispatchHubAfterQueuePane> {
  AgentDispatchSettings _settings = const AgentDispatchSettings();
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _settings = prefs.loadAgentDispatchSettings();
      _loaded = true;
    });
  }

  Future<void> _persist({
    List<AgentDispatchAfterStep>? steps,
    bool? runOnFailure,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final disk = prefs.loadAgentDispatchSettings();
    final next = disk.copyWith(
      hubAfterQueue: steps ?? _settings.hubAfterQueue,
      hubRunAfterQueueOnFailure:
          runOnFailure ?? _settings.hubRunAfterQueueOnFailure,
    );
    await prefs.saveAgentDispatchSettings(next);
    if (!mounted) return;
    setState(() => _settings = next);
  }

  @override
  Widget build(BuildContext context) {
    return AgentDispatchAfterQueueField(
      key: const ValueKey('agent-dispatch-hub-after-queue'),
      steps: _settings.hubAfterQueue,
      enabled: _loaded,
      description:
          'These actions run after every currently running dispatch batch finishes.',
      onChanged: (steps) => _persist(steps: steps),
      runOnFailure: _settings.hubRunAfterQueueOnFailure,
      onRunOnFailureChanged: (value) => _persist(runOnFailure: value),
    );
  }
}
