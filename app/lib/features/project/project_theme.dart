import 'package:flutter/material.dart';

import '../kanban/kanban_labels.dart';

/// 单个项目的颜色主题预设
class ProjectThemePreset {
  const ProjectThemePreset({
    required this.id,
    required this.name,
    required this.seedLight,
    required this.seedDark,
    required this.labelWork,
    required this.labelPersonal,
    required this.labelUrgent,
    required this.labelIdea,
    required this.priorityLow,
    required this.priorityMedium,
    required this.priorityHigh,
  });

  final String id;
  final String name;
  final Color seedLight;
  final Color seedDark;
  final Color labelWork;
  final Color labelPersonal;
  final Color labelUrgent;
  final Color labelIdea;
  final Color priorityLow;
  final Color priorityMedium;
  final Color priorityHigh;

  Color get defaultLabelColor => seedLight;

  Color priorityColor(CardPriority priority, ColorScheme scheme) =>
      switch (priority) {
        CardPriority.none => scheme.outline,
        CardPriority.low => priorityLow,
        CardPriority.medium => priorityMedium,
        CardPriority.high => priorityHigh,
      };

  List<KanbanLabel> get presetLabels => [
        KanbanLabel(key: 'work', name: '工作', color: labelWork),
        KanbanLabel(key: 'personal', name: '个人', color: labelPersonal),
        KanbanLabel(key: 'urgent', name: '紧急', color: labelUrgent),
        KanbanLabel(key: 'idea', name: '想法', color: labelIdea),
      ];
}

const kDefaultProjectThemeId = 'indigo';

const kProjectThemePresets = <ProjectThemePreset>[
  ProjectThemePreset(
    id: 'indigo',
    name: '靛蓝',
    seedLight: Color(0xFF4F6BED),
    seedDark: Color(0xFF8BA4FF),
    labelWork: Color(0xFF4F6BED),
    labelPersonal: Color(0xFF2E9E6A),
    labelUrgent: Color(0xFFE05252),
    labelIdea: Color(0xFF9B59B6),
    priorityLow: Color(0xFF2E9E6A),
    priorityMedium: Color(0xFFE09A2E),
    priorityHigh: Color(0xFFE05252),
  ),
  ProjectThemePreset(
    id: 'forest',
    name: '森林',
    seedLight: Color(0xFF2E7D56),
    seedDark: Color(0xFF6BBF8A),
    labelWork: Color(0xFF2E7D56),
    labelPersonal: Color(0xFF5A9E6E),
    labelUrgent: Color(0xFFC45C4A),
    labelIdea: Color(0xFF7A9B4F),
    priorityLow: Color(0xFF4A9B6E),
    priorityMedium: Color(0xFFD4A03C),
    priorityHigh: Color(0xFFC45C4A),
  ),
  ProjectThemePreset(
    id: 'sunset',
    name: '暮色',
    seedLight: Color(0xFFE07A3A),
    seedDark: Color(0xFFFFB07C),
    labelWork: Color(0xFFE07A3A),
    labelPersonal: Color(0xFFD4A03C),
    labelUrgent: Color(0xFFD64550),
    labelIdea: Color(0xFFB565A7),
    priorityLow: Color(0xFFD4A03C),
    priorityMedium: Color(0xFFE07A3A),
    priorityHigh: Color(0xFFD64550),
  ),
  ProjectThemePreset(
    id: 'ocean',
    name: '海洋',
    seedLight: Color(0xFF1A8FAD),
    seedDark: Color(0xFF5EC4E0),
    labelWork: Color(0xFF1A8FAD),
    labelPersonal: Color(0xFF2E9E9E),
    labelUrgent: Color(0xFFE05252),
    labelIdea: Color(0xFF5B7FBD),
    priorityLow: Color(0xFF2E9E9E),
    priorityMedium: Color(0xFFE09A2E),
    priorityHigh: Color(0xFFE05252),
  ),
  ProjectThemePreset(
    id: 'slate',
    name: '石墨',
    seedLight: Color(0xFF5C6B7A),
    seedDark: Color(0xFF9AA8B5),
    labelWork: Color(0xFF5C6B7A),
    labelPersonal: Color(0xFF6E8B74),
    labelUrgent: Color(0xFFB85C5C),
    labelIdea: Color(0xFF7A6E9B),
    priorityLow: Color(0xFF6E8B74),
    priorityMedium: Color(0xFFB8956A),
    priorityHigh: Color(0xFFB85C5C),
  ),
];

ProjectThemePreset projectThemeForId(String? id) {
  if (id == null || id.isEmpty) {
    return kProjectThemePresets.first;
  }
  return kProjectThemePresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => kProjectThemePresets.first,
  );
}

ThemeData buildKanbanTheme(ProjectThemePreset preset, Brightness brightness) {
  final seed = brightness == Brightness.dark ? preset.seedDark : preset.seedLight;
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    ),
    useMaterial3: true,
    fontFamilyFallback: const [
      'Microsoft YaHei',
      'PingFang SC',
      'Noto Sans CJK SC',
    ],
  );
}
