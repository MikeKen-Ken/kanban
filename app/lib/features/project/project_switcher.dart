import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../features/project/project_list_preferences.dart';
import '../../features/project/projects_manifest.dart';
import 'android_project_title.dart';
import 'project_quick_switch.dart';
import 'project_settings_screen.dart';
import 'project_theme.dart';
import '../../common/app_snack_bar.dart';
import '../agent_dispatch/agent_dispatch.dart';

/// 左上角项目切换器
class ProjectSwitcher extends StatelessWidget {
  const ProjectSwitcher({super.key});

  static const double _menuMinWidth = 360;
  static const double _menuMaxWidth = 440;

  /// 触发器最大宽度：短名随内容收缩，长名到此上限后省略
  static const double _titleMaxWidth = 320;

  Future<void> _createProject(BuildContext context) async {
    final controller = context.read<BoardController>();
    final textController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create project'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Project name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) {
      await controller.createProject(title);
    }
  }

  Future<void> _renameProject(
      BuildContext context, ProjectEntry project) async {
    final controller = context.read<BoardController>();
    final textController = TextEditingController(text: project.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: textController,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty && title != project.title) {
      await controller.renameProject(project.id, title);
    }
  }

  Future<void> _deleteProject(
      BuildContext context, ProjectEntry project) async {
    final controller = context.read<BoardController>();
    if (controller.projects.length <= 1) {
      showAppSnackBar(context, message: 'At least one project must remain');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text('"${project.title}" will be moved to Trash'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final deleted = await controller.deleteProject(project.id);
    if (!context.mounted) return;
    if (!deleted) {
      showAppSnackBar(context, message: 'Delete failed');
    }
  }

  Future<void> _resolveProjectConflict(
    BuildContext context,
    ProjectEntry project,
  ) async {
    final controller = context.read<BoardController>();
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync conflict'),
        content: Text(
          'The other side deleted "${project.title}", but this device has unsynced changes.\n'
          'Keep the project or confirm deletion to move it to Trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Confirm deletion'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keep project'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    await controller.resolveProjectConflict(
      project.id,
      keepProject: choice,
    );
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

  Color _projectSeedColor(String themeId, Brightness brightness) {
    final preset = projectThemeForId(themeId);
    return brightness == Brightness.dark ? preset.seedDark : preset.seedLight;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BoardController>(
      builder: (context, controller, _) {
        final active = controller.activeProject;
        final projects = controller.projects;
        final sortMode = controller.appSettings.projectSortMode;
        final isAndroid = Theme.of(context).platform == TargetPlatform.android;
        final rawTitle = active?.title ?? 'Board';
        final displayTitle =
            isAndroid ? androidCompactProjectTitle(rawTitle) : rawTitle;

        // 短按：完整菜单；稍长按住后上下滑动：快速切换项目
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProjectQuickSwitchGesture(
              projects: projects,
              activeProjectId: controller.activeProjectId,
              longPressDelay: controller.appSettings.dragDelay,
              themeIdFor: controller.themeIdForProject,
              onCommit: controller.switchProject,
              child: PopupMenuButton<String>(
                tooltip: isAndroid
                    ? 'Switch project: $rawTitle'
                    : 'Switch project (tap for menu, hold and drag to switch)',
                constraints: const BoxConstraints(
                  minWidth: _menuMinWidth,
                  maxWidth: _menuMaxWidth,
                ),
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
                  } else if (value.startsWith('__sort__:')) {
                    final modeName = value.substring('__sort__:'.length);
                    await controller.setProjectSortMode(
                      ProjectSortMode.fromName(modeName),
                    );
                  } else {
                    await controller.switchProject(value);
                  }
                },
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isAndroid ? 144 : _titleMaxWidth,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
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
                ),
                itemBuilder: (context) {
                  final theme = Theme.of(context);
                  final brightness = theme.brightness;
                  final subtitleStyle = theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  );

                  final items = <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      enabled: false,
                      height: 32,
                      child: Text('Sort by', style: subtitleStyle),
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
                      final seed = _projectSeedColor(
                        controller.themeIdForProject(project.id),
                        brightness,
                      );
                      final scheme = ColorScheme.fromSeed(
                        seedColor: seed,
                        brightness: brightness,
                      );
                      final tileBg = scheme.primaryContainer.withValues(
                        alpha: isActive ? 0.95 : 0.45,
                      );
                      final onTile = scheme.onPrimaryContainer;

                      return PopupMenuItem<String>(
                        value: project.id,
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          dense: true,
                          selected: isActive,
                          tileColor: tileBg,
                          selectedTileColor: tileBg,
                          selectedColor: onTile,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          leading: Icon(
                            isActive
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 18,
                            color: scheme.primary,
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  project.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: onTile,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (project.hasConflict) ...[
                                const SizedBox(width: 6),
                                Text(
                                  'Conflict',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (project.conflictDeleted)
                                IconButton(
                                  tooltip: 'Resolve sync conflict',
                                  icon: Icon(
                                    Icons.error_outline,
                                    size: 18,
                                    color: theme.colorScheme.error,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () async {
                                    Navigator.pop(context);
                                    await _resolveProjectConflict(
                                        context, project);
                                  },
                                ),
                              IconButton(
                                tooltip: 'Rename project',
                                icon: Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: onTile.withValues(alpha: 0.85),
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await _renameProject(context, project);
                                },
                              ),
                              IconButton(
                                tooltip: isPinned ? 'Unpin' : 'Pin',
                                icon: Icon(
                                  isPinned
                                      ? Icons.push_pin
                                      : Icons.push_pin_outlined,
                                  size: 18,
                                  color: isPinned
                                      ? scheme.primary
                                      : onTile.withValues(alpha: 0.85),
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await controller.toggleProjectPin(project.id);
                                },
                              ),
                              if (projects.length > 1)
                                IconButton(
                                  tooltip: 'Delete project',
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
                        ),
                      );
                    }),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: '__new__',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.add),
                        title: Text('Create project'),
                        dense: true,
                      ),
                    ),
                    const PopupMenuItem(
                      value: '__settings__',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.tune_outlined),
                        title: Text('Current project settings'),
                        dense: true,
                      ),
                    ),
                  ];
                  return items;
                },
              ),
            ),
            IconButton(
              tooltip: 'Create project',
              icon: const Icon(Icons.add),
              onPressed: () => _createProject(context),
            ),
            const AgentDispatchToolbarButton(),
          ],
        );
      },
    );
  }
}
