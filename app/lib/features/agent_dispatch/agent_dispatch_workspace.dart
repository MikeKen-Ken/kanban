import 'package:flutter/material.dart';

import 'agent_dispatch_card_status_pane.dart';
import 'agent_dispatch_displayed_card.dart';
import 'agent_dispatch_log.dart';
import 'agent_dispatch_progress.dart';
import 'agent_dispatch_section_header.dart';
import 'agent_interaction.dart';
import 'agent_interaction_prompt.dart';

export 'agent_dispatch_workspace_layout.dart';

class AgentDispatchWorkerPane extends StatelessWidget {
  const AgentDispatchWorkerPane({
    required this.workerStatus,
    required this.enabled,
    required this.onFixWorker,
    super.key,
  });

  final String? workerStatus;
  final bool enabled;
  final VoidCallback onFixWorker;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PaneTitle(
          title: 'Worker',
          tone: AgentDispatchSectionTone.worker,
        ),
        const SizedBox(height: 12),
        SelectableText(workerStatus ?? 'Checking…', style: textTheme.bodySmall),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enabled ? onFixWorker : null,
            icon: const Icon(Icons.build_outlined, size: 18),
            label: const Text('Repair Worker'),
          ),
        ),
      ],
    );
  }
}

class AgentDispatchSkillPane extends StatefulWidget {
  const AgentDispatchSkillPane({
    required this.skillPath,
    required this.skillPreview,
    required this.enabled,
    required this.onOpenSkillDirectory,
    required this.onRefreshSkill,
    super.key,
  });

  final String skillPath;
  final String? skillPreview;
  final bool enabled;
  final VoidCallback onOpenSkillDirectory;
  final VoidCallback onRefreshSkill;

  @override
  State<AgentDispatchSkillPane> createState() => _AgentDispatchSkillPaneState();
}

class _AgentDispatchSkillPaneState extends State<AgentDispatchSkillPane> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final canFill = constraints.maxHeight.isFinite &&
            constraints.maxHeight > 160 &&
            _expanded;
        final preview = Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              widget.skillPreview ?? '(Skill not found or unreadable)',
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('agent-dispatch-skill-expand'),
                  tooltip: _expanded ? 'Collapse skill' : 'Expand skill',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                  ),
                ),
                const Expanded(
                  child: _PaneTitle(
                    title: 'Skill',
                    tone: AgentDispatchSectionTone.skill,
                  ),
                ),
                IconButton(
                  tooltip: 'Open skill folder',
                  onPressed:
                      widget.enabled ? widget.onOpenSkillDirectory : null,
                  icon: const Icon(Icons.folder_open_outlined, size: 20),
                ),
                IconButton(
                  tooltip: 'Reload skill',
                  onPressed: widget.enabled ? widget.onRefreshSkill : null,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
            if (_expanded) ...[
              Text(
                widget.skillPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (canFill)
                Expanded(child: preview)
              else
                SizedBox(height: 280, child: preview),
            ],
          ],
        );
      },
    );
  }
}

class AgentDispatchLogPane extends StatefulWidget {
  const AgentDispatchLogPane({
    required this.controller,
    required this.running,
    required this.onClear,
    required this.onExport,
    required this.onCopy,
    this.progress = AgentDispatchProgress.idle,
    this.pendingInteraction,
    this.onInteractionReply,
    super.key,
  });

  final TextEditingController controller;
  final bool running;
  final VoidCallback onClear;
  final ValueChanged<String> onExport;
  final ValueChanged<String> onCopy;
  final AgentDispatchProgress progress;
  final AgentInteractionEvent? pendingInteraction;
  final Future<bool> Function(String text)? onInteractionReply;

  @override
  State<AgentDispatchLogPane> createState() => _AgentDispatchLogPaneState();
}

class _AgentDispatchLogPaneState extends State<AgentDispatchLogPane> {
  /// PopupMenuButton 不会在选中 null 时触发 [PopupMenuButton.onSelected]。
  static const _allTasksMenuValue = 0;

  final _scrollController = ScrollController();
  AgentDispatchLogSource? _sourceFilter;
  AgentDispatchLogLevel? _levelFilter;
  int? _taskFilter;
  var _pinToBottom = true;
  String? _cachedText;
  AgentDispatchLogSource? _cachedSourceFilter;
  AgentDispatchLogLevel? _cachedLevelFilter;
  int? _cachedTaskFilter;
  List<String> _cachedLines = const [];
  List<AgentDispatchLogTask> _cachedTasks = const [];

  static const _bottomThreshold = 48.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onLogChanged);
  }

  @override
  void didUpdateWidget(covariant AgentDispatchLogPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onLogChanged);
    widget.controller.addListener(_onLogChanged);
  }

  bool get _isAtBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - _bottomThreshold;
  }

  void _onUserScroll() {
    _pinToBottom = _isAtBottom;
  }

  void _onLogChanged() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || !_pinToBottom) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _jumpToRunningCard(int? ordinal) {
    if (ordinal == null) return;
    setState(() {
      _taskFilter = ordinal;
      _pinToBottom = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  List<String> _visibleLines() {
    final text = widget.controller.text;
    if (_cachedText == text &&
        _cachedSourceFilter == _sourceFilter &&
        _cachedLevelFilter == _levelFilter &&
        _cachedTaskFilter == _taskFilter) {
      return _cachedLines;
    }
    _cachedText = text;
    _cachedSourceFilter = _sourceFilter;
    _cachedLevelFilter = _levelFilter;
    _cachedTaskFilter = _taskFilter;
    final lines = text.split('\n');
    _cachedTasks = AgentDispatchLogTasks.parse(lines);
    final taskFilter = _taskFilter != null &&
            _cachedTasks.any((task) => task.ordinal == _taskFilter)
        ? _taskFilter
        : null;
    _cachedLines = [
      for (var i = 0; i < lines.length; i++)
        if (!AgentDispatchLogEntry.isLowValue(lines[i]) &&
            (taskFilter == null ||
                AgentDispatchLogTasks.ordinalOfLine(_cachedTasks, i) ==
                    taskFilter) &&
            (_sourceFilter == null ||
                AgentDispatchLogEntry.sourceOf(lines[i]) == _sourceFilter) &&
            (_levelFilter == null ||
                AgentDispatchLogEntry.levelOf(lines[i]) == _levelFilter))
          lines[i],
    ];
    return _cachedLines;
  }

  _LogSummary _summary() {
    final allLines = widget.controller.text.split('\n').where(
          (line) => !AgentDispatchLogEntry.isLowValue(line),
        );
    var errors = 0;
    var warnings = 0;
    String? totalTokens;
    for (final line in allLines) {
      final level = AgentDispatchLogEntry.levelOf(line);
      if (level == AgentDispatchLogLevel.error) errors++;
      if (level == AgentDispatchLogLevel.warning) warnings++;
      final match = RegExp(r'\btotal=(\d+)').firstMatch(line);
      if (match != null) totalTokens = match.group(1);
    }
    return _LogSummary(
        errors: errors, warnings: warnings, totalTokens: totalTokens);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onLogChanged);
    _scrollController.dispose();
    super.dispose();
  }

  List<TextSpan> _lineSpans(BuildContext context, String line) {
    final displayedLine = AgentDispatchLogEntry.displayLine(line);
    final level = AgentDispatchLogEntry.levelOf(line);
    final source = AgentDispatchLogEntry.sourceOf(line);
    final baseColor = _lineColor(context, level, source);
    final emphasisColor = Theme.of(context).colorScheme.primary;
    const baseStyle = TextStyle(fontFamily: 'Consolas', fontSize: 12);

    return [
      for (final segment in AgentDispatchLogHighlight.segments(displayedLine))
        TextSpan(
          text: segment.text,
          style: baseStyle.copyWith(
            color: segment.emphasis ? emphasisColor : baseColor,
            fontWeight: segment.emphasis ? FontWeight.w600 : null,
          ),
        ),
    ];
  }

  Color _lineColor(
    BuildContext context,
    AgentDispatchLogLevel level,
    AgentDispatchLogSource source,
  ) {
    if (level == AgentDispatchLogLevel.error) {
      return Theme.of(context).colorScheme.error;
    }
    if (level == AgentDispatchLogLevel.warning) {
      return Colors.orange.shade800;
    }
    if (level == AgentDispatchLogLevel.success) {
      return Colors.green.shade700;
    }
    return switch (source) {
      AgentDispatchLogSource.system =>
        Theme.of(context).colorScheme.onSurfaceVariant,
      AgentDispatchLogSource.worker => Colors.indigo.shade700,
      AgentDispatchLogSource.ai => Colors.teal.shade700,
      AgentDispatchLogSource.mcp => Colors.deepOrange.shade700,
      AgentDispatchLogSource.shell => Colors.brown.shade700,
    };
  }

  Widget _taskFilterMenu(List<AgentDispatchLogTask> tasks, int? selectedTask) {
    final label = selectedTask == null
        ? 'All tasks'
        : tasks.firstWhere((task) => task.ordinal == selectedTask).label;
    return PopupMenuButton<int>(
      key: const ValueKey('agent-dispatch-log-task-filter'),
      tooltip: 'Filter logs by task',
      initialValue: selectedTask ?? _allTasksMenuValue,
      onSelected: (value) {
        setState(() {
          _taskFilter = value == _allTasksMenuValue ? null : value;
          _pinToBottom = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          _scrollController.jumpTo(0);
        });
      },
      itemBuilder: (context) => [
        const PopupMenuItem<int>(
          key: ValueKey('agent-dispatch-log-task-all'),
          value: _allTasksMenuValue,
          child: Text('All tasks'),
        ),
        for (final task in tasks)
          PopupMenuItem<int>(
            key: ValueKey('agent-dispatch-log-task-${task.ordinal}'),
            value: task.ordinal,
            child: Text(task.label),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _sourceLegend(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final source in AgentDispatchLogSource.values)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _sourceFilter = _sourceFilter == source ? null : source;
                  _pinToBottom = true;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_scrollController.hasClients) return;
                  _scrollController.jumpTo(0);
                });
              },
              child: Text(
                source.label,
                key: ValueKey('agent-dispatch-log-source-${source.name}'),
                style: style?.copyWith(
                  color: _lineColor(
                    context,
                    AgentDispatchLogLevel.info,
                    source,
                  ).withValues(
                    alpha: _sourceFilter == null || _sourceFilter == source
                        ? 1
                        : 0.35,
                  ),
                  fontWeight: _sourceFilter == source ? FontWeight.w700 : null,
                  decoration:
                      _sourceFilter == source ? TextDecoration.underline : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _summaryChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    AgentDispatchLogLevel? filter,
  }) {
    final selected = filter != null && _levelFilter == filter;
    return InkWell(
      key: filter == null
          ? null
          : ValueKey('agent-dispatch-log-level-${filter.name}'),
      borderRadius: BorderRadius.circular(8),
      onTap: filter == null
          ? null
          : () {
              setState(() {
                _levelFilter = selected ? null : filter;
                _pinToBottom = true;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_scrollController.hasClients) return;
                _scrollController.jumpTo(0);
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.22 : 0.1),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: color.withValues(alpha: selected ? 0.8 : 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text('$label ', style: const TextStyle(fontSize: 11)),
            Text(value,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _logLine(BuildContext context, String line) {
    final level = AgentDispatchLogEntry.levelOf(line);
    final source = AgentDispatchLogEntry.sourceOf(line);
    final color = _lineColor(context, level, source);
    final isAlert = level == AgentDispatchLogLevel.error ||
        level == AgentDispatchLogLevel.warning;
    final icon = switch (level) {
      AgentDispatchLogLevel.error => Icons.error_outline,
      AgentDispatchLogLevel.warning => Icons.warning_amber_rounded,
      AgentDispatchLogLevel.success => Icons.check_circle_outline,
      AgentDispatchLogLevel.info => Icons.circle_outlined,
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isAlert ? color.withValues(alpha: 0.09) : null,
        borderRadius: BorderRadius.circular(4),
        border:
            isAlert ? Border(left: BorderSide(color: color, width: 3)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 6),
            child: Icon(icon, size: 14, color: color),
          ),
          Expanded(
            child: SelectableText.rich(
              TextSpan(children: _lineSpans(context, line)),
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLog = widget.controller.text.isNotEmpty;
    final lines = _visibleLines();
    final tasks = _cachedTasks;
    final selectedTask =
        _taskFilter != null && tasks.any((task) => task.ordinal == _taskFilter)
            ? _taskFilter
            : null;
    final rawActionLog = AgentDispatchLogTasks.slice(
      widget.controller.text,
      selectedTask,
    );
    final actionLog = AgentDispatchLogEntry.displayText(rawActionLog);
    final canAct = actionLog.trim().isNotEmpty;
    final summary = _summary();
    final displayed = AgentDispatchDisplayedCard.resolve(
      fullLog: widget.controller.text,
      tasks: tasks,
      selectedOrdinal: selectedTask,
      live: widget.progress,
      batchRunning: widget.running,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: _PaneTitle(
                title: 'Run log',
                tone: AgentDispatchSectionTone.log,
              ),
            ),
            if (tasks.isNotEmpty) ...[
              Flexible(
                  child: Align(
                alignment: Alignment.centerRight,
                child: _taskFilterMenu(tasks, selectedTask),
              )),
              const SizedBox(width: 4),
            ],
            IconButton(
              tooltip: 'Clear log',
              onPressed: widget.running || !hasLog ? null : widget.onClear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            ),
            IconButton(
              key: const ValueKey('agent-dispatch-log-export'),
              tooltip: 'Export log',
              onPressed: canAct ? () => widget.onExport(actionLog) : null,
              icon: const Icon(Icons.file_download_outlined, size: 20),
            ),
            IconButton(
              key: const ValueKey('agent-dispatch-log-copy'),
              tooltip: 'Copy log',
              onPressed: canAct ? () => widget.onCopy(actionLog) : null,
              icon: const Icon(Icons.copy_outlined, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _sourceLegend(context),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _summaryChip(
              icon: Icons.error_outline,
              label: 'Error',
              value: '${summary.errors}',
              color: Theme.of(context).colorScheme.error,
              filter: AgentDispatchLogLevel.error,
            ),
            _summaryChip(
              icon: Icons.warning_amber_rounded,
              label: 'Warning',
              value: '${summary.warnings}',
              color: Colors.orange.shade800,
              filter: AgentDispatchLogLevel.warning,
            ),
            _summaryChip(
              icon: Icons.token_outlined,
              label: 'Latest token',
              value: summary.totalTokens ?? '—',
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
        const SizedBox(height: 8),
        AgentDispatchCardStatusPane(
          progress: displayed.progress,
          running: displayed.running,
          logText: AgentDispatchLogEntry.displayText(displayed.logSlice),
          showJumpToRunning: displayed.canJumpToRunning,
          onJumpToRunning: displayed.canJumpToRunning
              ? () => _jumpToRunningCard(displayed.runningOrdinal)
              : null,
        ),
        if (widget.pendingInteraction != null &&
            widget.onInteractionReply != null) ...[
          const SizedBox(height: 8),
          AgentInteractionPrompt(
            event: widget.pendingInteraction!,
            onReply: widget.onInteractionReply!,
            autoShowDialog: widget.pendingInteraction!.choices.isNotEmpty,
          ),
        ],
        const SizedBox(height: 8),
        if (displayed.running)
          LinearProgressIndicator(value: displayed.progress.fraction),
        if (displayed.running) const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  _onUserScroll();
                  return false;
                },
                child: ListView.builder(
                  key: const ValueKey('agent-dispatch-log-scroll'),
                  controller: _scrollController,
                  itemCount: lines.length,
                  itemBuilder: (context, index) =>
                      _logLine(context, lines[index]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LogSummary {
  const _LogSummary({
    required this.errors,
    required this.warnings,
    required this.totalTokens,
  });

  final int errors;
  final int warnings;
  final String? totalTokens;
}

class _PaneTitle extends StatelessWidget {
  const _PaneTitle({required this.title, required this.tone});

  final String title;
  final AgentDispatchSectionTone tone;

  @override
  Widget build(BuildContext context) {
    return AgentDispatchSectionHeader(title: title, tone: tone);
  }
}
