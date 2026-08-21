import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../../settings/settings_section.dart';
import '../attachments/card_attachment_image.dart';
import '../automations/automation_rules_screen.dart';
import '../kanban/swimlane.dart';
import '../wallpapers/wallpaper_image.dart';
import '../wallpapers/wallpaper_library_dialog.dart';
import '../wallpapers/wallpaper_models.dart';
import 'project_mcp_tag_chips.dart';
import 'project_mcp_tags.dart';
import 'project_settings.dart';
import 'project_theme.dart';

/// 当前项目的设置页（设置项会同步到 WebDAV）
class ProjectSettingsScreen extends StatefulWidget {
  const ProjectSettingsScreen({super.key});

  @override
  State<ProjectSettingsScreen> createState() => _ProjectSettingsScreenState();
}

class _ProjectSettingsScreenState extends State<ProjectSettingsScreen> {
  late final TextEditingController _doneColumnController;
  late String _selectedThemeId;
  late Map<String, int> _wipLimits;
  late SwimlaneMode _swimlaneMode;
  late List<String> _agentMcpTags;
  double? _overlayDraft;
  double? _cardOpacityDraft;
  bool _saving = false;
  bool _backgroundBusy = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<BoardController>().projectSettings;
    _doneColumnController =
        TextEditingController(text: settings.doneColumnName);
    _selectedThemeId =
        settings.themeId.isEmpty ? kDefaultProjectThemeId : settings.themeId;
    _wipLimits = Map<String, int>.from(settings.columnWipLimits);
    _swimlaneMode = settings.swimlaneMode;
    _agentMcpTags = List<String>.from(settings.agentMcpTags);
  }

  @override
  void dispose() {
    _doneColumnController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _doneColumnController.text.trim();
    if (name.isEmpty) {
      showAppSnackBar(context, message: 'Done column name cannot be empty');
      return;
    }

    setState(() => _saving = true);
    final controller = context.read<BoardController>();
    final themeId =
        _selectedThemeId == kDefaultProjectThemeId ? '' : _selectedThemeId;
    // note: 主动保存视为采用当前编辑结果，一并清除未解决的设置冲突
    await controller.saveProjectSettings(
      controller.projectSettings.copyWith(
        doneColumnName: name,
        themeId: themeId,
        columnWipLimits: _wipLimits,
        swimlaneMode: _swimlaneMode,
        agentMcpTags: _agentMcpTags,
        clearConflictSide: true,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    showAppSnackBar(context,
        message: 'Project settings saved and will sync automatically');
    Navigator.pop(context);
  }

  Future<void> _pickBackground() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const WallpaperLibraryDialog(),
    );
  }

  Future<void> _clearBackground() async {
    setState(() => _backgroundBusy = true);
    await context.read<BoardController>().setProjectWallpapers(
      wallpaperIds: const [],
      mode: WallpaperPlaybackMode.fixed,
      intervalSeconds: ProjectSettings.defaultWallpaperIntervalSeconds,
    );
    if (!mounted) return;
    setState(() {
      _backgroundBusy = false;
      _overlayDraft = null;
      _cardOpacityDraft = null;
    });
    showAppSnackBar(context, message: 'Background image cleared');
  }

  Future<void> _resolveConflict({required bool keepPrimary}) async {
    final controller = context.read<BoardController>();
    await controller.resolveSettingsConflict(keepPrimary: keepPrimary);
    if (!mounted) return;
    final settings = controller.projectSettings;
    setState(() {
      _doneColumnController.text = settings.doneColumnName;
      _selectedThemeId =
          settings.themeId.isEmpty ? kDefaultProjectThemeId : settings.themeId;
      _wipLimits = Map<String, int>.from(settings.columnWipLimits);
      _agentMcpTags = List<String>.from(settings.agentMcpTags);
      _overlayDraft = null;
      _cardOpacityDraft = null;
    });
    showAppSnackBar(
      context,
      message: keepPrimary
          ? 'Kept the current project settings'
          : 'Switched to the other project settings',
    );
  }

  String _themeLabel(String themeId) {
    final id = themeId.isEmpty ? kDefaultProjectThemeId : themeId;
    return projectThemeForId(id).name;
  }

  String _conflictSummary(ProjectSettings primary, ProjectSettings other) {
    final parts = <String>[];
    if (primary.doneColumnName != other.doneColumnName) {
      parts.add('Done column: "${other.doneColumnName}"');
    }
    if (primary.themeId != other.themeId) {
      parts.add('Theme: ${_themeLabel(other.themeId)}');
    }
    if (primary.backgroundAttachmentId != other.backgroundAttachmentId) {
      parts.add(other.hasBackgroundImage
          ? 'Background image differs'
          : 'No custom background image');
    }
    if ((primary.backgroundOverlayOpacity - other.backgroundOverlayOpacity)
            .abs() >=
        0.001) {
      parts.add(
        'Background overlay: ${(other.backgroundOverlayOpacity * 100).round()}%',
      );
    }
    if ((primary.cardSurfaceOpacity - other.cardSurfaceOpacity).abs() >=
        0.001) {
      parts.add(
        'Card opacity: ${(other.cardSurfaceOpacity * 100).round()}%',
      );
    }
    final prefsDiffer =
        primary.columnPreferences.length != other.columnPreferences.length ||
            primary.columnPreferences.keys.any((key) {
              final a = primary.columnPreferences[key];
              final b = other.columnPreferences[key];
              if (a == null || b == null) return true;
              return a.sortMode != b.sortMode ||
                  a.pinnedCardIds.join(',') != b.pinnedCardIds.join(',');
            });
    if (prefsDiffer) {
      parts.add('Column sorting or pinning preferences differ');
    }
    if (primary.columnWipLimits.toString() !=
        other.columnWipLimits.toString()) {
      parts.add('Column WIP limits differ');
    }
    if (_agentMcpTagsSummary(primary.agentMcpTags) !=
        _agentMcpTagsSummary(other.agentMcpTags)) {
      parts.add('Project MCP: ${_agentMcpTagsSummary(other.agentMcpTags)}');
    }
    if (parts.isEmpty) {
      return 'The other side has older or empty default settings; keeping the current copy is usually best';
    }
    return 'Other side: ${parts.join('; ')}';
  }

  String _agentMcpTagsSummary(List<String> tags) {
    if (tags.isEmpty) return 'None';
    final names = [
      for (final option in kProjectMcpTagOptions)
        if (tags.contains(option.key)) option.name,
      for (final tag in tags)
        if (!kProjectMcpTagKeys.contains(tag)) tag,
    ];
    return names.join('、');
  }

  Future<void> _toggleAgentMcpTag(String key, bool selected) async {
    if (selected == _agentMcpTags.contains(key)) return;
    final next = selected
        ? [..._agentMcpTags, key]
        : _agentMcpTags.where((item) => item != key).toList();
    setState(() => _agentMcpTags = next);
    final controller = context.read<BoardController>();
    await controller.saveProjectSettings(
      controller.projectSettings.copyWith(agentMcpTags: next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewPreset = projectThemeForId(_selectedThemeId);
    final controller = context.watch<BoardController>();
    final projectTitle = controller.activeProject?.title ?? 'Project';
    final settings = controller.projectSettings;
    final rotationWallpaperCount =
        settings.wallpaperPlaybackMode == WallpaperPlaybackMode.random
            ? controller.wallpapers.length
            : settings.wallpaperIds.length;
    final overlayValue = (_overlayDraft ?? settings.backgroundOverlayOpacity)
        .clamp(0.0, ProjectSettings.maxBackgroundOverlayOpacity);
    final cardOpacityValue =
        (_cardOpacityDraft ?? settings.cardSurfaceOpacity).clamp(
      ProjectSettings.minCardSurfaceOpacity,
      ProjectSettings.defaultCardSurfaceOpacity,
    );

    return Theme(
      data: buildKanbanTheme(
        previewPreset,
        theme.brightness,
      ),
      child: Scaffold(
        appBar: AppBar(title: Text('$projectTitle Settings')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (settings.hasConflict && settings.conflictSide != null) ...[
              Material(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sync conflict: another copy of the project settings exists',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _conflictSummary(settings, settings.conflictSide!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () =>
                                _resolveConflict(keepPrimary: true),
                            child: const Text('Keep current'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                _resolveConflict(keepPrimary: false),
                            child: const Text('Keep other'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            SettingsSection(
              icon: Icons.palette_outlined,
              title: 'Theme',
              subtitle:
                  'Choose a color scheme for this project; it follows the project when you switch',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: kProjectThemePresets.map((preset) {
                      final selected = _selectedThemeId == preset.id;
                      return _ThemeOptionTile(
                        preset: preset,
                        selected: selected,
                        onTap: () =>
                            setState(() => _selectedThemeId = preset.id),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              icon: Icons.memory_outlined,
              title: 'Agent MCP',
              subtitle:
                  'The Worker injects the scoped Kanban MCP by default; add other MCPs for this project here',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProjectMcpTagChips(
                        selectedKeys: _agentMcpTags,
                        onSelected: _toggleAgentMcpTag,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'These tags sync with the project. The Worker injects the selected MCPs only when needed.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              icon: Icons.wallpaper_outlined,
              title: 'Board background',
              subtitle:
                  'The wallpaper library is shared and synced across projects; images are cached locally',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: AspectRatio(
                            aspectRatio: 16 / 10,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: settings.hasBackgroundImage
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (settings.wallpaperIds.isNotEmpty)
                                          WallpaperImage(
                                            wallpaperId:
                                                settings.wallpaperIds.first,
                                            thumb: true,
                                          )
                                        else
                                          CardAttachmentImage(
                                            attachmentId:
                                                settings.backgroundAttachmentId,
                                            thumb: true,
                                            fit: BoxFit.cover,
                                            showMissingLabel: true,
                                          ),
                                        if (overlayValue > 0)
                                          ColoredBox(
                                            color: Colors.black.withValues(
                                              alpha: overlayValue,
                                            ),
                                          ),
                                      ],
                                    )
                                  : ColoredBox(
                                      color: theme
                                          .colorScheme.surfaceContainerHighest,
                                      child: Center(
                                        child: Text(
                                          'No background image; using the theme color',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _backgroundBusy ? null : _pickBackground,
                            icon: _backgroundBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.image_outlined),
                            label: Text(
                              settings.hasBackgroundImage
                                  ? 'Manage wallpapers'
                                  : 'Open wallpaper library',
                            ),
                          ),
                          if (settings.hasBackgroundImage)
                            OutlinedButton.icon(
                              onPressed:
                                  _backgroundBusy ? null : _clearBackground,
                              icon: const Icon(Icons.hide_image_outlined),
                              label: const Text('Clear'),
                            ),
                        ],
                      ),
                      if (settings.hasBackgroundImage) ...[
                        if (settings.wallpaperPlaybackMode ==
                                WallpaperPlaybackMode.random &&
                            rotationWallpaperCount > 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Randomly rotating $rotationWallpaperCount wallpapers; '
                              'switching every ${settings.wallpaperIntervalSeconds}s',
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Overlay: ${(overlayValue * 100).round()}%',
                          style: theme.textTheme.labelLarge,
                        ),
                        Slider(
                          value: overlayValue,
                          min: 0,
                          max: ProjectSettings.maxBackgroundOverlayOpacity,
                          divisions: 14,
                          label: '${(overlayValue * 100).round()}%',
                          onChanged: _backgroundBusy
                              ? null
                              : (value) {
                                  setState(() => _overlayDraft = value);
                                },
                          onChangeEnd: (value) async {
                            await controller
                                .setBoardBackgroundOverlayOpacity(value);
                            if (!mounted) return;
                            setState(() => _overlayDraft = null);
                          },
                        ),
                        Text(
                          'A darker overlay improves column and text readability on complex backgrounds',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Card opacity: ${(cardOpacityValue * 100).round()}%',
                        style: theme.textTheme.labelLarge,
                      ),
                      Slider(
                        value: cardOpacityValue,
                        min: ProjectSettings.minCardSurfaceOpacity,
                        max: ProjectSettings.defaultCardSurfaceOpacity,
                        divisions: 13,
                        label: '${(cardOpacityValue * 100).round()}%',
                        onChanged: _backgroundBusy
                            ? null
                            : (value) {
                                setState(() => _cardOpacityDraft = value);
                              },
                        onChangeEnd: (value) async {
                          await controller.setCardSurfaceOpacity(value);
                          if (!mounted) return;
                          setState(() => _cardOpacityDraft = null);
                        },
                      ),
                      Text(
                        '100% keeps cards solid; lower values make them translucent while keeping titles and text clear',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              icon: Icons.view_kanban_outlined,
              title: 'Board',
              subtitle:
                  'These settings belong to the current project and sync across devices through WebDAV',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextFormField(
                    controller: _doneColumnController,
                    decoration: const InputDecoration(
                      labelText: 'Done column name',
                      hintText: ProjectSettings.defaultDoneColumnName,
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText:
                          'Completed cards move here. Changing this name also renames the corresponding column.',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: DropdownButtonFormField<SwimlaneMode>(
                    value: _swimlaneMode,
                    decoration: const InputDecoration(
                      labelText: 'Swimlane grouping',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final mode in SwimlaneMode.values)
                        DropdownMenuItem(
                          value: mode,
                          child: Text(mode.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _swimlaneMode = value);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.bolt_outlined),
                  title: const Text('Automation rules'),
                  subtitle: Text(
                    '${controller.projectSettings.automationRules.length} configured',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AutomationRulesScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              icon: Icons.speed_outlined,
              title: 'Incomplete card limits',
              subtitle:
                  'Cards are highlighted at the limit, but adding and moving remain allowed',
              collapsible: true,
              initiallyExpanded: false,
              children: [
                for (final column
                    in controller.board?.columns ?? const <KanbanColumn>[])
                  ListTile(
                    title: Text(column.title),
                    subtitle: Text(
                      (_wipLimits[column.id] ?? 0) < 1
                          ? 'Unlimited'
                          : 'Suggested maximum: ${_wipLimits[column.id]} incomplete cards',
                    ),
                    trailing: SizedBox(
                      width: 150,
                      child: Slider(
                        value: (_wipLimits[column.id] ?? 0)
                            .clamp(0, 20)
                            .toDouble(),
                        min: 0,
                        max: 20,
                        divisions: 20,
                        label: (_wipLimits[column.id] ?? 0) < 1
                            ? 'Unlimited'
                            : '${_wipLimits[column.id]}',
                        onChanged: (value) {
                          setState(() {
                            final limit = value.round();
                            if (limit < 1) {
                              _wipLimits.remove(column.id);
                            } else {
                              _wipLimits[column.id] = limit;
                            }
                          });
                        },
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.cloud_sync_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Theme and board options are saved when you click Save. Agent MCP tags, background, overlay, and card opacity apply and sync immediately.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ProjectThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final swatches = [
      preset.seedLight,
      preset.labelImportantUrgent,
      preset.labelImportantNotUrgent,
      preset.labelUrgentNotImportant,
      preset.labelNeither,
      preset.labelNeedResource,
    ];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 108,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : scheme.surfaceContainerLow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final color in swatches)
                  Expanded(
                    child: Container(
                      height: 14,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preset.name,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.check_circle,
                  size: 16,
                  color: scheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
