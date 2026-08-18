import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../kanban/next_work_card.dart';
import '../kanban/verify_column.dart';
import '../project/project_list_preferences.dart';
import '../project/projects_manifest.dart';
import 'agent_dispatch_progress.dart';
import 'agent_dispatch_registry.dart';
import 'agent_dispatch_window.dart';

class AgentDispatchHubItem {
  const AgentDispatchHubItem({
    required this.projectId,
    required this.title,
    required this.running,
    this.isCurrent = false,
    this.progressLabel,
    this.progressFraction,
  });

  final String projectId;
  final String title;
  final bool running;
  final bool isCurrent;
  final String? progressLabel;
  final double? progressFraction;
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
        );
      },
    );
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
    );
  }
}

class AgentDispatchHubView extends StatelessWidget {
  const AgentDispatchHubView({
    required this.items,
    required this.onClose,
    required this.onOpenProject,
    super.key,
  });

  final List<AgentDispatchHubItem> items;
  final VoidCallback onClose;
  final void Function(String projectId) onOpenProject;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = (viewport.width - 96).clamp(480.0, 720.0).toDouble();
    final dialogHeight = (viewport.height - 180).clamp(360.0, 640.0).toDouble();
    final runningCount = items.where((item) => item.running).length;
    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      title: Text(
        runningCount > 0 ? 'Agent 调度总览（$runningCount 个运行中）' : 'Agent 调度总览',
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: items.isEmpty
            ? const Center(child: Text('还没有看板项目'))
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _HubProjectTile(
                    item: item,
                    onOpen: () => onOpenProject(item.projectId),
                  );
                },
              ),
      ),
      actions: [
        TextButton(onPressed: onClose, child: const Text('关闭')),
      ],
    );
  }
}

class _HubProjectTile extends StatelessWidget {
  const _HubProjectTile({required this.item, required this.onOpen});

  final AgentDispatchHubItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = item.running
        ? (item.progressLabel == null ? '运行中' : '运行中 · ${item.progressLabel}')
        : '未运行';
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
                '当前',
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
          if (item.running) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: item.progressFraction),
          ],
        ],
      ),
      trailing: TextButton(
        onPressed: onOpen,
        child: Text(item.running ? '查看' : '打开'),
      ),
      onTap: onOpen,
    );
  }
}
