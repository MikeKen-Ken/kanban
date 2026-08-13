import 'package:flutter/material.dart';

import 'agent_dispatch_log.dart';

/// Agent 调度面板的桌面工作区。
///
/// 宽窗口使用「配置与 Worker / Skill / 对话记录」三列布局；窄窗口则
/// 回退为纵向滚动，避免字段被压缩到不可用。
class AgentDispatchWorkspace extends StatelessWidget {
  const AgentDispatchWorkspace({
    required this.worker,
    required this.skill,
    required this.settings,
    required this.log,
    super.key,
  });

  final Widget worker;
  final Widget skill;
  final Widget settings;
  final Widget log;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1040) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ScrollablePane(
                        title: '调度配置',
                        child: settings,
                      ),
                    ),
                    const Divider(height: 32),
                    worker,
                  ],
                ),
              ),
              const VerticalDivider(width: 25),
              Expanded(flex: 9, child: skill),
              const VerticalDivider(width: 25),
              Expanded(flex: 12, child: log),
            ],
          );
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PaneTitle(title: '调度配置'),
              const SizedBox(height: 12),
              settings,
              const Divider(height: 32),
              worker,
              const Divider(height: 32),
              SizedBox(height: 400, child: skill),
              const Divider(height: 32),
              SizedBox(height: 400, child: log),
            ],
          ),
        );
      },
    );
  }
}

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
        const _PaneTitle(title: 'Worker'),
        const SizedBox(height: 12),
        SelectableText(workerStatus ?? '检查中…', style: textTheme.bodySmall),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enabled ? onFixWorker : null,
            icon: const Icon(Icons.build_outlined, size: 18),
            label: const Text('一键修复 Worker'),
          ),
        ),
      ],
    );
  }
}

class AgentDispatchSkillPane extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _PaneTitle(title: 'Skill')),
            IconButton(
              tooltip: '打开 Skill 目录',
              onPressed: enabled ? onOpenSkillDirectory : null,
              icon: const Icon(Icons.folder_open_outlined, size: 20),
            ),
            IconButton(
              tooltip: '重新读取 Skill',
              onPressed: enabled ? onRefreshSkill : null,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        Text(
          skillPath,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                skillPreview ?? '（未找到或无法读取 Skill）',
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
              ),
            ),
          ),
        ),
      ],
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
    super.key,
  });

  final TextEditingController controller;
  final bool running;
  final VoidCallback onClear;
  final VoidCallback onExport;
  final VoidCallback onCopy;

  @override
  State<AgentDispatchLogPane> createState() => _AgentDispatchLogPaneState();
}

class _AgentDispatchLogPaneState extends State<AgentDispatchLogPane> {
  final _scrollController = ScrollController();

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

  void _onLogChanged() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onLogChanged);
    _scrollController.dispose();
    super.dispose();
  }

  List<TextSpan> _lineSpans(BuildContext context, String line) {
    final level = AgentDispatchLogEntry.levelOf(line);
    final source = AgentDispatchLogEntry.sourceOf(line);
    final baseColor = _lineColor(context, level, source);
    final emphasisColor = Theme.of(context).colorScheme.primary;
    const baseStyle = TextStyle(fontFamily: 'Consolas', fontSize: 12);

    return [
      for (final segment in AgentDispatchLogHighlight.segments(line))
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

  Widget _sourceLegend(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final source in AgentDispatchLogSource.values)
          Text(
            source.label,
            style: style?.copyWith(
              color: _lineColor(
                context,
                AgentDispatchLogLevel.info,
                source,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLog = widget.controller.text.isNotEmpty;
    final lines = widget.controller.text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _PaneTitle(title: '运行日志')),
            IconButton(
              tooltip: '清空记录',
              onPressed: widget.running || !hasLog ? null : widget.onClear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            ),
            IconButton(
              tooltip: '导出记录',
              onPressed: hasLog ? widget.onExport : null,
              icon: const Icon(Icons.file_download_outlined, size: 20),
            ),
            IconButton(
              tooltip: '复制记录',
              onPressed: hasLog ? widget.onCopy : null,
              icon: const Icon(Icons.copy_outlined, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _sourceLegend(context),
        const SizedBox(height: 8),
        if (widget.running) const LinearProgressIndicator(),
        if (widget.running) const SizedBox(height: 8),
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
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SelectableText.rich(
                  TextSpan(
                    children: [
                      for (var index = 0; index < lines.length; index++) ...[
                        ..._lineSpans(context, lines[index]),
                        if (index < lines.length - 1) const TextSpan(text: '\n'),
                      ],
                    ],
                  ),
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollablePane extends StatelessWidget {
  const _ScrollablePane({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaneTitle(title: title),
        const SizedBox(height: 12),
        Expanded(child: SingleChildScrollView(child: child)),
      ],
    );
  }
}

class _PaneTitle extends StatelessWidget {
  const _PaneTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleSmall);
  }
}
