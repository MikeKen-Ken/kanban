import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../project/projects_manifest.dart';

/// 集中展示并解决当前工作区中已发现的同步冲突。
class ConflictCenterScreen extends StatelessWidget {
  const ConflictCenterScreen({super.key});

  void _showResolved(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _choiceButtons({
    required BuildContext context,
    required String primaryLabel,
    required String otherLabel,
    required Future<void> Function(bool keepPrimary) onResolve,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonal(
          onPressed: () => onResolve(true),
          child: Text(primaryLabel),
        ),
        OutlinedButton(
          onPressed: () => onResolve(false),
          child: Text(otherLabel),
        ),
      ],
    );
  }

  Widget _boardTitleConflict(
    BuildContext context,
    BoardController controller,
  ) {
    final board = controller.board!;
    return _ConflictCard(
      icon: Icons.dashboard_outlined,
      title: '看板标题',
      description: '当前：${board.title}\n另一侧：${board.conflictTitle}',
      actions: _choiceButtons(
        context: context,
        primaryLabel: '保留当前标题',
        otherLabel: '采用另一侧标题',
        onResolve: (keepPrimary) async {
          await controller.resolveBoardTitleConflict(
            keepPrimary: keepPrimary,
          );
          if (context.mounted) _showResolved(context, '看板标题冲突已解决');
        },
      ),
    );
  }

  Widget _projectTitleConflict(
    BuildContext context,
    BoardController controller,
    ProjectEntry project,
  ) {
    return _ConflictCard(
      icon: Icons.folder_outlined,
      title: '项目名称 · ${project.title}',
      description: '当前：${project.title}\n另一侧：${project.conflictTitle}',
      actions: _choiceButtons(
        context: context,
        primaryLabel: '保留当前名称',
        otherLabel: '采用另一侧名称',
        onResolve: (keepPrimary) async {
          await controller.resolveProjectTitleConflict(
            project.id,
            keepPrimary: keepPrimary,
          );
          if (context.mounted) _showResolved(context, '项目名称冲突已解决');
        },
      ),
    );
  }

  Widget _projectDeleteConflict(
    BuildContext context,
    BoardController controller,
    ProjectEntry project,
  ) {
    return _ConflictCard(
      icon: Icons.folder_delete_outlined,
      title: '项目删改冲突 · ${project.title}',
      description: '另一侧删除了此项目，但当前一侧仍有修改。',
      actions: _choiceButtons(
        context: context,
        primaryLabel: '保留项目',
        otherLabel: '删除并移入回收站',
        onResolve: (keepPrimary) async {
          await controller.resolveProjectConflict(
            project.id,
            keepProject: keepPrimary,
          );
          if (context.mounted) _showResolved(context, '项目删改冲突已解决');
        },
      ),
    );
  }

  Widget _settingsConflict(
    BuildContext context,
    BoardController controller,
  ) {
    return _ConflictCard(
      icon: Icons.tune_outlined,
      title: '当前项目设置',
      description: '当前项目设置与另一侧同时发生了修改。',
      actions: _choiceButtons(
        context: context,
        primaryLabel: '保留当前设置',
        otherLabel: '采用另一侧设置',
        onResolve: (keepPrimary) async {
          await controller.resolveSettingsConflict(keepPrimary: keepPrimary);
          if (context.mounted) _showResolved(context, '项目设置冲突已解决');
        },
      ),
    );
  }

  Widget _cardConflict(
    BuildContext context,
    BoardController controller,
    String columnId,
    KanbanCard card,
  ) {
    final description = card.conflictDeleted
        ? '另一侧已删除此卡片。选择删除后，卡片会进入回收站。'
        : '当前：${card.title}\n另一侧：${card.conflictSide?.title ?? '未知副本'}';
    return _ConflictCard(
      icon: Icons.sticky_note_2_outlined,
      title: '卡片 · ${card.title}',
      description: description,
      actions: _choiceButtons(
        context: context,
        primaryLabel: '保留当前',
        otherLabel: card.conflictDeleted ? '删除并移入回收站' : '采用另一份',
        onResolve: (keepPrimary) async {
          await controller.resolveCardConflict(
            columnId,
            card.id,
            keepPrimary
                ? CardConflictResolution.keepPrimary
                : CardConflictResolution.keepOther,
          );
          if (context.mounted) _showResolved(context, '卡片冲突已解决');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BoardController>(
      builder: (context, controller, _) {
        final board = controller.board;
        final projectConflicts = controller.manifest?.projects
                .where((project) => project.hasConflict)
                .toList() ??
            const <ProjectEntry>[];
        final cardConflicts = <({String columnId, KanbanCard card})>[];
        if (board != null) {
          for (final column in board.columns) {
            for (final card in column.cards) {
              if (card.hasConflict) {
                cardConflicts.add((columnId: column.id, card: card));
              }
            }
          }
        }

        final hasConflicts = board?.conflictTitle != null ||
            controller.projectSettings.hasConflict ||
            projectConflicts.isNotEmpty ||
            cardConflicts.isNotEmpty;

        return Scaffold(
          appBar: AppBar(title: const Text('冲突中心')),
          body: !hasConflicts
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 52),
                      SizedBox(height: 12),
                      Text('没有未解决的冲突'),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '请逐项选择要保留的内容。解决结果会保存到本机并参与下次同步。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    if (board?.conflictTitle != null)
                      _boardTitleConflict(context, controller),
                    for (final project in projectConflicts) ...[
                      if (project.conflictTitle != null)
                        _projectTitleConflict(context, controller, project),
                      if (project.conflictDeleted)
                        _projectDeleteConflict(context, controller, project),
                    ],
                    if (controller.projectSettings.hasConflict)
                      _settingsConflict(context, controller),
                    for (final conflict in cardConflicts)
                      _cardConflict(
                        context,
                        controller,
                        conflict.columnId,
                        conflict.card,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 12),
            actions,
          ],
        ),
      ),
    );
  }
}
