import 'package:flutter/material.dart';

/// Agent 调度面板的桌面工作区。
///
/// 宽窗口使用「配置 / Skill 与 Worker / 对话记录」三列布局；窄窗口则
/// 回退为纵向滚动，避免字段被压缩到不可用。
class AgentDispatchWorkspace extends StatelessWidget {
  const AgentDispatchWorkspace({
    required this.settings,
    required this.skillAndWorker,
    required this.log,
    super.key,
  });

  final Widget settings;
  final Widget skillAndWorker;
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
                child: _ScrollablePane(
                  title: '调度配置',
                  child: settings,
                ),
              ),
              const VerticalDivider(width: 25),
              Expanded(flex: 9, child: skillAndWorker),
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
              SizedBox(height: 400, child: skillAndWorker),
              const Divider(height: 32),
              SizedBox(height: 400, child: log),
            ],
          ),
        );
      },
    );
  }
}

class AgentDispatchSkillWorkerPane extends StatelessWidget {
  const AgentDispatchSkillWorkerPane({
    required this.skillPath,
    required this.skillPreview,
    required this.workerStatus,
    required this.enabled,
    required this.onOpenSkillDirectory,
    required this.onRefreshSkill,
    required this.onFixWorker,
    super.key,
  });

  final String skillPath;
  final String? skillPreview;
  final String? workerStatus;
  final bool enabled;
  final VoidCallback onOpenSkillDirectory;
  final VoidCallback onRefreshSkill;
  final VoidCallback onFixWorker;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _PaneTitle(title: 'Skill 与 Worker')),
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
        const SizedBox(height: 14),
        Text('Worker', style: textTheme.labelLarge),
        const SizedBox(height: 4),
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

class AgentDispatchLogPane extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final hasLog = controller.text.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _PaneTitle(title: '工具对话记录')),
            IconButton(
              tooltip: '清空记录',
              onPressed: running || !hasLog ? null : onClear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            ),
            IconButton(
              tooltip: '导出记录',
              onPressed: hasLog ? onExport : null,
              icon: const Icon(Icons.file_download_outlined, size: 20),
            ),
            IconButton(
              tooltip: '复制记录',
              onPressed: hasLog ? onCopy : null,
              icon: const Icon(Icons.copy_outlined, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (running) const LinearProgressIndicator(),
        if (running) const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: controller,
              readOnly: true,
              maxLines: null,
              expands: true,
              scrollPhysics: const AlwaysScrollableScrollPhysics(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.all(12),
              ),
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
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
