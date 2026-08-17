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
  }

  @override
  void dispose() {
    _doneColumnController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _doneColumnController.text.trim();
    if (name.isEmpty) {
      showAppSnackBar(context, message: '已完成列名称不能为空');
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
        clearConflictSide: true,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    showAppSnackBar(context, message: '项目设置已保存，将自动同步');
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
    showAppSnackBar(context, message: '已清除背景图');
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
      _overlayDraft = null;
      _cardOpacityDraft = null;
    });
    showAppSnackBar(context, message: keepPrimary ? '已保留当前项目设置' : '已改用另一侧项目设置');
  }

  String _themeLabel(String themeId) {
    final id = themeId.isEmpty ? kDefaultProjectThemeId : themeId;
    return projectThemeForId(id).name;
  }

  String _conflictSummary(ProjectSettings primary, ProjectSettings other) {
    final parts = <String>[];
    if (primary.doneColumnName != other.doneColumnName) {
      parts.add('已完成列：「${other.doneColumnName}」');
    }
    if (primary.themeId != other.themeId) {
      parts.add('主题：${_themeLabel(other.themeId)}');
    }
    if (primary.backgroundAttachmentId != other.backgroundAttachmentId) {
      parts.add(other.hasBackgroundImage ? '背景图不同' : '无自定义背景图');
    }
    if ((primary.backgroundOverlayOpacity - other.backgroundOverlayOpacity)
            .abs() >=
        0.001) {
      parts.add(
        '背景遮罩：${(other.backgroundOverlayOpacity * 100).round()}%',
      );
    }
    if ((primary.cardSurfaceOpacity - other.cardSurfaceOpacity).abs() >=
        0.001) {
      parts.add(
        '卡片不透明度：${(other.cardSurfaceOpacity * 100).round()}%',
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
      parts.add('列排序/置顶偏好不同');
    }
    if (primary.columnWipLimits.toString() !=
        other.columnWipLimits.toString()) {
      parts.add('列 WIP 上限不同');
    }
    if (parts.isEmpty) {
      return '另一侧为较旧或空默认设置，通常保留当前即可';
    }
    return '另一侧：${parts.join('；')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewPreset = projectThemeForId(_selectedThemeId);
    final controller = context.watch<BoardController>();
    final projectTitle = controller.activeProject?.title ?? '项目';
    final settings = controller.projectSettings;
    final overlayValue = (_overlayDraft ?? settings.backgroundOverlayOpacity)
        .clamp(0.0, ProjectSettings.maxBackgroundOverlayOpacity);
    final cardOpacityValue =
        (_cardOpacityDraft ?? settings.cardSurfaceOpacity).clamp(
      ProjectSettings.minCardSurfaceOpacity,
      ProjectSettings.maxCardSurfaceOpacity,
    );

    return Theme(
      data: buildKanbanTheme(
        previewPreset,
        theme.brightness,
      ),
      child: Scaffold(
        appBar: AppBar(title: Text('$projectTitle 设置')),
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
                        '同步冲突：项目设置存在另一份副本',
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
                            child: const Text('保留当前'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                _resolveConflict(keepPrimary: false),
                            child: const Text('保留另一份'),
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
              title: '主题',
              subtitle: '为当前项目选择颜色搭配，切换项目后主题会随之变化',
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
              icon: Icons.wallpaper_outlined,
              title: '看板背景',
              subtitle: '壁纸库跨项目复用并同步；图片缓存到本地，随机轮播不会重复请求远端',
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
                                          '未设置背景图，使用主题底色',
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
                              settings.hasBackgroundImage ? '管理与选择壁纸' : '打开壁纸库',
                            ),
                          ),
                          if (settings.hasBackgroundImage)
                            OutlinedButton.icon(
                              onPressed:
                                  _backgroundBusy ? null : _clearBackground,
                              icon: const Icon(Icons.hide_image_outlined),
                              label: const Text('清除'),
                            ),
                        ],
                      ),
                      if (settings.hasBackgroundImage) ...[
                        if (settings.wallpaperPlaybackMode ==
                                WallpaperPlaybackMode.random &&
                            settings.wallpaperIds.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '随机轮播 ${settings.wallpaperIds.length} 张，每 '
                              '${settings.wallpaperIntervalSeconds} 秒切换',
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '遮罩：${(overlayValue * 100).round()}%',
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
                          '加深遮罩可提高列与文字在复杂背景上的可读性',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '卡片不透明度：${(cardOpacityValue * 100).round()}%',
                        style: theme.textTheme.labelLarge,
                      ),
                      Slider(
                        value: cardOpacityValue,
                        min: ProjectSettings.minCardSurfaceOpacity,
                        max: ProjectSettings.maxCardSurfaceOpacity,
                        divisions: 20,
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
                        '100% 会保持实色；降低后卡片底色半透明，可透过磨砂层看到壁纸，标题与文字仍保持清晰',
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
              title: '看板',
              subtitle: '此页面的设置属于当前项目，会通过 WebDAV 在多设备间同步',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextFormField(
                    controller: _doneColumnController,
                    decoration: const InputDecoration(
                      labelText: '已完成列名称',
                      hintText: ProjectSettings.defaultDoneColumnName,
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText: '勾选完成或拖入该列时，卡片会移入此列。修改后会同步重命名对应列。',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: DropdownButtonFormField<SwimlaneMode>(
                    value: _swimlaneMode,
                    decoration: const InputDecoration(
                      labelText: '泳道分组',
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
                  title: const Text('自动化规则'),
                  subtitle: Text(
                    '已配置 ${controller.projectSettings.automationRules.length} 条',
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
              title: '未完成卡片上限',
              subtitle: '达到上限时高亮并提醒，但不会阻止继续添加或移动',
              collapsible: true,
              initiallyExpanded: false,
              children: [
                for (final column
                    in controller.board?.columns ?? const <KanbanColumn>[])
                  ListTile(
                    title: Text(column.title),
                    subtitle: Text(
                      (_wipLimits[column.id] ?? 0) < 1
                          ? '不限'
                          : '建议最多 ${_wipLimits[column.id]} 张未完成卡片',
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
                            ? '不限'
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
                  : const Text('保存'),
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
                    '主题与看板选项点「保存」后写入；背景图、遮罩与卡片不透明度会立即生效并同步到 WebDAV。',
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
