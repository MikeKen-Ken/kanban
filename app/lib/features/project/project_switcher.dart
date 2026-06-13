import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../features/project/project_list_preferences.dart';
import '../../features/project/projects_manifest.dart';
import 'project_settings_screen.dart';

/// 左上角项目切换器
class ProjectSwitcher extends StatelessWidget {
  const ProjectSwitcher({super.key});

  Future<void> _createProject(BuildContext context) async {
    final controller = context.read<BoardController>();
    final textController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建项目'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '项目名称'),
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
      await controller.createProject(title);
    }
  }

  Future<void> _renameProject(BuildContext context, ProjectEntry project) async {
    final controller = context.read<BoardController>();
    final textController = TextEditingController(text: project.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名项目'),
        content: TextField(
          controller: textController,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty && title != project.title) {
      if (project.id == controller.activeProjectId) {
        await controller.renameActiveProject(title);
      }
      // note: 非当前项目的重命名通过同步 manifest 处理，暂仅支持当前项目
    }
  }

  Future<void> _deleteProject(BuildContext context, ProjectEntry project) async {
    final controller = context.read<BoardController>();
    if (controller.projects.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要保留一个项目')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除项目？'),
        content: Text('「${project.title}」将移至回收站'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final deleted = await controller.deleteProject(project.id);
    if (!context.mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败')),
      );
    }
  }

  Widget _sortModeTile(
    BuildContext context, {
    required ProjectSortMode mode,
    required ProjectSortMode current,
  }) {
    final theme = Theme.of(context);
    final selected = mode == current;
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: selected
              ? Icon(
                  Icons.check,
                  size: 18,
                  color: theme.colorScheme.primary,
                )
              : null,
        ),
        const SizedBox(width: 8),
        Text(mode.label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BoardController>(
      builder: (context, controller, _) {
        final active = controller.activeProject;
        final projects = controller.projects;
        final sortMode = controller.appSettings.projectSortMode;

        return PopupMenuButton<String>(
          tooltip: '切换项目',
          onSelected: (value) async {
            if (value == '__new__') {
              await _createProject(context);
            } else if (value == '__settings__') {
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProjectSettingsScreen(),
                ),
              );
            } else if (value == '__rename__') {
              if (active != null) {
                await _renameProject(context, active);
              }
            } else if (value.startsWith('__sort__:')) {
              final modeName = value.substring('__sort__:'.length);
              await controller.setProjectSortMode(
                ProjectSortMode.fromName(modeName),
              );
            } else {
              await controller.switchProject(value);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_outlined, size: 20),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    active?.title ?? '看板',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
          itemBuilder: (context) {
            final theme = Theme.of(context);
            final subtitleStyle = theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            );

            final items = <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                enabled: false,
                height: 32,
                child: Text('排序方式', style: subtitleStyle),
              ),
              for (final mode in ProjectSortMode.values)
                PopupMenuItem<String>(
                  value: '__sort__:${mode.name}',
                  child: _sortModeTile(
                    context,
                    mode: mode,
                    current: sortMode,
                  ),
                ),
              const PopupMenuDivider(),
              ...projects.map((project) {
                final isActive = project.id == controller.activeProjectId;
                final isPinned = controller.isProjectPinned(project.id);
                return PopupMenuItem<String>(
                  enabled: false,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: Icon(
                      isActive
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: isActive ? theme.colorScheme.primary : null,
                    ),
                    title: Text(
                      project.title,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: isPinned ? '取消置顶' : '置顶',
                          icon: Icon(
                            isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                            size: 18,
                            color: isPinned ? theme.colorScheme.primary : null,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () async {
                            Navigator.pop(context);
                            await controller.toggleProjectPin(project.id);
                          },
                        ),
                        if (projects.length > 1)
                          IconButton(
                            tooltip: '删除项目',
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              Navigator.pop(context);
                              await _deleteProject(context, project);
                            },
                          ),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, project.id),
                  ),
                );
              }),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: '__new__',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.add),
                  title: Text('新建项目'),
                  dense: true,
                ),
              ),
              if (active != null)
                const PopupMenuItem(
                  value: '__rename__',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('重命名当前项目'),
                    dense: true,
                  ),
                ),
              const PopupMenuItem(
                value: '__settings__',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune_outlined),
                  title: Text('当前项目设置'),
                  dense: true,
                ),
              ),
            ];
            return items;
          },
        );
      },
    );
  }
}
