import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../../settings/settings_section.dart';
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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<BoardController>().projectSettings;
    _doneColumnController =
        TextEditingController(text: settings.doneColumnName);
    _selectedThemeId =
        settings.themeId.isEmpty ? kDefaultProjectThemeId : settings.themeId;
    _wipLimits = Map<String, int>.from(settings.columnWipLimits);
  }

  @override
  void dispose() {
    _doneColumnController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _doneColumnController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已完成列名称不能为空')),
      );
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
        clearConflictSide: true,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('项目设置已保存，将自动同步')),
    );
    Navigator.pop(context);
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
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(keepPrimary ? '已保留当前项目设置' : '已改用另一侧项目设置'),
      ),
    );
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
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              icon: Icons.speed_outlined,
              title: '在制品上限',
              subtitle: '达到上限时高亮并提醒，但不会阻止继续添加或移动',
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
                    '保存后设置会写入当前项目数据，并在下次同步时上传到 WebDAV。',
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
      preset.labelWork,
      preset.labelPersonal,
      preset.labelUrgent,
      preset.labelIdea,
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
