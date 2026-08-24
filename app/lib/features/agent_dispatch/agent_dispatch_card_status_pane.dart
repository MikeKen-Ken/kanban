import 'dart:async';

import 'package:flutter/material.dart';

import 'agent_dispatch_card_metrics.dart';
import 'agent_dispatch_progress.dart';

/// 运行日志上方的当前卡片状态区：进度、标题与运行指标。
class AgentDispatchCardStatusPane extends StatefulWidget {
  const AgentDispatchCardStatusPane({
    required this.progress,
    required this.running,
    required this.logText,
    this.showJumpToRunning = false,
    this.onJumpToRunning,
    super.key,
  });

  final AgentDispatchProgress progress;
  final bool running;
  final String logText;
  final bool showJumpToRunning;
  final VoidCallback? onJumpToRunning;

  @override
  State<AgentDispatchCardStatusPane> createState() =>
      _AgentDispatchCardStatusPaneState();
}

class _AgentDispatchCardStatusPaneState
    extends State<AgentDispatchCardStatusPane> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AgentDispatchCardStatusPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (!widget.running) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = widget.progress.phaseLabel.trim().isEmpty
        ? (widget.running ? 'Running' : 'Idle')
        : widget.progress.phaseLabel;
    final title = widget.progress.currentTitle.trim();
    final detail = widget.progress.currentDetail.trim();
    final parsed = AgentDispatchCardMetrics.parse(
      widget.logText,
      running: widget.running,
    );
    final metrics = parsed.hasAny || widget.running ? parsed : null;

    return Container(
      key: const ValueKey('agent-dispatch-task-status'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                widget.progress.liveCardLabel,
                key: const ValueKey('agent-dispatch-task-progress'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                key: const ValueKey('agent-dispatch-task-phase'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  phase,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.showJumpToRunning &&
                  widget.onJumpToRunning != null) ...[
                const Spacer(),
                TextButton.icon(
                  key: const ValueKey('agent-dispatch-jump-running-card'),
                  onPressed: widget.onJumpToRunning,
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('Live card'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title.isEmpty ? 'No active card' : title,
            key: const ValueKey('agent-dispatch-task-title'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              key: const ValueKey('agent-dispatch-task-detail'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (metrics != null) ...[
            const SizedBox(height: 8),
            _MetricsRow(
              metrics: metrics,
              running: widget.running,
              liveElapsedSeconds:
                  widget.running ? widget.progress.cardElapsedSeconds() : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({
    required this.metrics,
    required this.running,
    this.liveElapsedSeconds,
  });

  final AgentDispatchCardMetrics metrics;
  final bool running;
  final int? liveElapsedSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[];

    final token = metrics.token;
    if (token != null) {
      chips.add(
        _MetricChip(
          key: const ValueKey('agent-dispatch-card-token'),
          icon: Icons.token_outlined,
          label: 'Token',
          value: formatAgentDispatchTokenCount(token.totalTokens),
          hint: 'Input ${formatAgentDispatchTokenCount(token.inputTokens)} · '
              'output ${formatAgentDispatchTokenCount(token.outputTokens)}',
          color: theme.colorScheme.primary,
        ),
      );
    } else if (running) {
      chips.add(
        _MetricChip(
          key: const ValueKey('agent-dispatch-card-token'),
          icon: Icons.token_outlined,
          label: 'Token',
          value: 'Loading',
          color: theme.colorScheme.primary,
        ),
      );
    }

    final elapsedSeconds = running && liveElapsedSeconds != null
        ? liveElapsedSeconds
        : metrics.elapsedSeconds;
    if (elapsedSeconds != null) {
      chips.add(
        _MetricChip(
          key: const ValueKey('agent-dispatch-card-elapsed'),
          icon: Icons.timer_outlined,
          label: 'Time',
          value: formatAgentDispatchElapsed(elapsedSeconds),
          color: theme.colorScheme.tertiary,
        ),
      );
    }

    if (metrics.steps != null || metrics.toolCalls != null) {
      final parts = <String>[];
      if (metrics.steps != null) parts.add('Steps ${metrics.steps}');
      if (metrics.toolCalls != null) parts.add('Tools ${metrics.toolCalls}');
      chips.add(
        _MetricChip(
          key: const ValueKey('agent-dispatch-card-activity'),
          icon: Icons.hub_outlined,
          label: 'Activity',
          value: parts.join(' · '),
          color: Colors.teal.shade700,
        ),
      );
    }

    final engine = metrics.engine?.trim();
    final model = metrics.model?.trim();
    if ((engine != null && engine.isNotEmpty) ||
        (model != null && model.isNotEmpty && model != '(平台默认)')) {
      final value = [
        if (engine != null && engine.isNotEmpty) engine,
        if (model != null && model.isNotEmpty && model != '(platform default)')
          model,
      ].join(' · ');
      chips.add(
        _MetricChip(
          key: const ValueKey('agent-dispatch-card-engine'),
          icon: Icons.smart_toy_outlined,
          label: 'Engine',
          value: value,
          color: Colors.indigo.shade700,
        ),
      );
    }

    if (metrics.retryCount > 0) {
      chips.add(
        _MetricChip(
          key: const ValueKey('agent-dispatch-card-retry'),
          icon: Icons.replay_outlined,
          label: 'Retries',
          value: '${metrics.retryCount} retries',
          color: Colors.orange.shade800,
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      key: const ValueKey('agent-dispatch-card-metrics'),
      spacing: 8,
      runSpacing: 6,
      children: chips,
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.hint,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text('$label ', style: const TextStyle(fontSize: 11)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (hint == null) return child;
    return Tooltip(message: hint!, child: child);
  }
}
