import 'package:flutter/material.dart';

import '../kanban/kanban_labels.dart';

// 语义色提供稳定的色相区分，主题色只影响明暗和整体气质。
Color _distinctLabelColor(Color themeColor, Color semanticColor) =>
    Color.lerp(themeColor, semanticColor, 0.42)!;

const _semanticUrgent = Color(0xFFE05252);
const _semanticImportant = Color(0xFF3F6BED);
const _semanticSecondary = Color(0xFF2E9E6A);
const _semanticNeutral = Color(0xFF9B59B6);
const _semanticResource = Color(0xFFB7791F);
const _semanticDevelopment = Color(0xFF6B4FD3);
const _semanticConsultation = Color(0xFF16878A);
const _semanticDocumentation = Color(0xFFA84A2A);
const _semanticAcceptance = Color(0xFF2E8B57);

/// 单个项目的颜色主题预设
class ProjectThemePreset {
  const ProjectThemePreset({
    required this.id,
    required this.name,
    required this.seedLight,
    required this.seedDark,
    required this.labelImportantUrgent,
    required this.labelImportantNotUrgent,
    required this.labelUrgentNotImportant,
    required this.labelNeither,
    required this.labelNeedResource,
    required this.labelDevelopment,
    required this.labelConsultation,
    required this.labelDocumentation,
    required this.labelAcceptance,
    required this.priorityLow,
    required this.priorityMedium,
    required this.priorityHigh,
  });

  final String id;
  final String name;
  final Color seedLight;
  final Color seedDark;

  /// 重要紧急
  final Color labelImportantUrgent;

  /// 重要不急
  final Color labelImportantNotUrgent;

  /// 次要紧急
  final Color labelUrgentNotImportant;

  /// 次要不急
  final Color labelNeither;

  /// 缺外部资源 / 暂不具备开工条件
  final Color labelNeedResource;

  /// 可由代理实施的代码类需求
  final Color labelDevelopment;

  /// 只需答复、解释或建议的需求
  final Color labelConsultation;

  /// 可在卡片 Markdown 中交付的内容
  final Color labelDocumentation;

  /// 已完成并通过验收的需求
  final Color labelAcceptance;
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

  /// 当前预置：艾森豪威尔四象限、缺资源和工作类型。
  List<KanbanLabel> get presetLabels => [
        KanbanLabel(
          key: 'important_urgent',
          name: '重要紧急',
          description: '重要且紧急',
          color: _distinctLabelColor(labelImportantUrgent, _semanticUrgent),
        ),
        KanbanLabel(
          key: 'important_not_urgent',
          name: '重要不急',
          description: '重要不紧急',
          color:
              _distinctLabelColor(labelImportantNotUrgent, _semanticImportant),
        ),
        KanbanLabel(
          key: 'urgent_not_important',
          name: '次要紧急',
          description: '紧急不重要',
          color:
              _distinctLabelColor(labelUrgentNotImportant, _semanticSecondary),
        ),
        KanbanLabel(
          key: 'not_urgent_not_important',
          name: '次要不急',
          description: '不重要不紧急',
          color: _distinctLabelColor(labelNeither, _semanticNeutral),
        ),
        KanbanLabel(
          key: 'need_resource',
          name: '缺资源',
          color: _distinctLabelColor(labelNeedResource, _semanticResource),
        ),
        KanbanLabel(
          key: 'development',
          name: '开发',
          description: '可由代理实施的代码类需求',
          color: _distinctLabelColor(labelDevelopment, _semanticDevelopment),
        ),
        KanbanLabel(
          key: 'consultation',
          name: '咨询',
          description: '只需答复、解释或建议',
          color: _distinctLabelColor(labelConsultation, _semanticConsultation),
        ),
        KanbanLabel(
          key: 'documentation',
          name: '文档',
          description: '可在卡片 Markdown 中交付的内容',
          color:
              _distinctLabelColor(labelDocumentation, _semanticDocumentation),
        ),
        KanbanLabel(
          key: 'needs_verify',
          name: '验收',
          description: '需要代理做本地验收与适用验证后再交人工确认',
          color: _distinctLabelColor(labelAcceptance, _semanticAcceptance),
        ),
      ];

  /// 旧预置（工作/个人/紧急/想法）：仅解析显示，不进入新选标签列表。
  /// 颜色复用象限色槽，避免为主题再维护一套废弃色。
  List<KanbanLabel> get legacyPresetLabels => [
        KanbanLabel(
          key: 'work',
          name: '工作（旧）',
          description: '旧预置标签，新项目请改用象限标签',
          color: labelImportantNotUrgent,
        ),
        KanbanLabel(
          key: 'personal',
          name: '个人（旧）',
          description: '旧预置标签，新项目请改用象限标签',
          color: labelUrgentNotImportant,
        ),
        KanbanLabel(
          key: 'urgent',
          name: '紧急（旧）',
          description: '旧预置标签，新项目请改用象限标签',
          color: labelImportantUrgent,
        ),
        KanbanLabel(
          key: 'idea',
          name: '想法（旧）',
          description: '旧预置标签，新项目请改用象限标签',
          color: labelNeither,
        ),
      ];
}

const kDefaultProjectThemeId = 'indigo';

const kProjectThemePresets = <ProjectThemePreset>[
  ProjectThemePreset(
    id: 'indigo',
    name: '靛蓝',
    seedLight: Color(0xFF4F6BED),
    seedDark: Color(0xFF8BA4FF),
    labelImportantUrgent: Color(0xFFE05252),
    labelImportantNotUrgent: Color(0xFF4F6BED),
    labelUrgentNotImportant: Color(0xFF2E9E6A),
    labelNeither: Color(0xFF9B59B6),
    labelNeedResource: Color(0xFF8B7355),
    labelDevelopment: Color(0xFF5B5BD6),
    labelConsultation: Color(0xFF16878A),
    labelDocumentation: Color(0xFF8B5E3C),
    labelAcceptance: Color(0xFF3C8D62),
    priorityLow: Color(0xFF2E9E6A),
    priorityMedium: Color(0xFFE09A2E),
    priorityHigh: Color(0xFFE05252),
  ),
  ProjectThemePreset(
    id: 'forest',
    name: '森林',
    seedLight: Color(0xFF2E7D56),
    seedDark: Color(0xFF6BBF8A),
    labelImportantUrgent: Color(0xFFC45C4A),
    labelImportantNotUrgent: Color(0xFF2E7D56),
    labelUrgentNotImportant: Color(0xFF5A9E6E),
    labelNeither: Color(0xFF7A9B4F),
    labelNeedResource: Color(0xFF8A7A4E),
    labelDevelopment: Color(0xFF5272B8),
    labelConsultation: Color(0xFF368C79),
    labelDocumentation: Color(0xFF8A6848),
    labelAcceptance: Color(0xFF4E9A70),
    priorityLow: Color(0xFF4A9B6E),
    priorityMedium: Color(0xFFD4A03C),
    priorityHigh: Color(0xFFC45C4A),
  ),
  ProjectThemePreset(
    id: 'sunset',
    name: '暮色',
    seedLight: Color(0xFFE07A3A),
    seedDark: Color(0xFFFFB07C),
    labelImportantUrgent: Color(0xFFD64550),
    labelImportantNotUrgent: Color(0xFFE07A3A),
    labelUrgentNotImportant: Color(0xFFD4A03C),
    labelNeither: Color(0xFFB565A7),
    labelNeedResource: Color(0xFF9A6B4A),
    labelDevelopment: Color(0xFF7766B8),
    labelConsultation: Color(0xFF4B9382),
    labelDocumentation: Color(0xFF8F5F42),
    labelAcceptance: Color(0xFF4B9368),
    priorityLow: Color(0xFFD4A03C),
    priorityMedium: Color(0xFFE07A3A),
    priorityHigh: Color(0xFFD64550),
  ),
  ProjectThemePreset(
    id: 'ocean',
    name: '海洋',
    seedLight: Color(0xFF1A8FAD),
    seedDark: Color(0xFF5EC4E0),
    labelImportantUrgent: Color(0xFFE05252),
    labelImportantNotUrgent: Color(0xFF1A8FAD),
    labelUrgentNotImportant: Color(0xFF2E9E9E),
    labelNeither: Color(0xFF5B7FBD),
    labelNeedResource: Color(0xFF7A6E58),
    labelDevelopment: Color(0xFF536FB2),
    labelConsultation: Color(0xFF238B8C),
    labelDocumentation: Color(0xFF786247),
    labelAcceptance: Color(0xFF3D9474),
    priorityLow: Color(0xFF2E9E9E),
    priorityMedium: Color(0xFFE09A2E),
    priorityHigh: Color(0xFFE05252),
  ),
  ProjectThemePreset(
    id: 'slate',
    name: '石墨',
    seedLight: Color(0xFF5C6B7A),
    seedDark: Color(0xFF9AA8B5),
    labelImportantUrgent: Color(0xFFB85C5C),
    labelImportantNotUrgent: Color(0xFF5C6B7A),
    labelUrgentNotImportant: Color(0xFF6E8B74),
    labelNeither: Color(0xFF7A6E9B),
    labelNeedResource: Color(0xFF8A7B68),
    labelDevelopment: Color(0xFF6672A8),
    labelConsultation: Color(0xFF527F78),
    labelDocumentation: Color(0xFF7B6653),
    labelAcceptance: Color(0xFF568B6A),
    priorityLow: Color(0xFF6E8B74),
    priorityMedium: Color(0xFFB8956A),
    priorityHigh: Color(0xFFB85C5C),
  ),
  ProjectThemePreset(
    id: 'rose',
    name: '玫瑰',
    seedLight: Color(0xFFC45B7A),
    seedDark: Color(0xFFE89BB4),
    labelImportantUrgent: Color(0xFFD64550),
    labelImportantNotUrgent: Color(0xFFC45B7A),
    labelUrgentNotImportant: Color(0xFFD4896A),
    labelNeither: Color(0xFF9B6EAD),
    labelNeedResource: Color(0xFF9A7A62),
    labelDevelopment: Color(0xFF735FA8),
    labelConsultation: Color(0xFF4A8B83),
    labelDocumentation: Color(0xFF90654F),
    labelAcceptance: Color(0xFF4B966D),
    priorityLow: Color(0xFF6E9B7A),
    priorityMedium: Color(0xFFD4896A),
    priorityHigh: Color(0xFFD64550),
  ),
  ProjectThemePreset(
    id: 'violet',
    name: '紫罗兰',
    seedLight: Color(0xFF7B5EA7),
    seedDark: Color(0xFFB69AD9),
    labelImportantUrgent: Color(0xFFC45C6A),
    labelImportantNotUrgent: Color(0xFF7B5EA7),
    labelUrgentNotImportant: Color(0xFF5B8FA8),
    labelNeither: Color(0xFF9B7EBD),
    labelNeedResource: Color(0xFF8B735F),
    labelDevelopment: Color(0xFF6956A5),
    labelConsultation: Color(0xFF4E8886),
    labelDocumentation: Color(0xFF80604D),
    labelAcceptance: Color(0xFF4B9272),
    priorityLow: Color(0xFF5B8FA8),
    priorityMedium: Color(0xFFC9A04A),
    priorityHigh: Color(0xFFC45C6A),
  ),
  ProjectThemePreset(
    id: 'amber',
    name: '琥珀',
    seedLight: Color(0xFFC9922E),
    seedDark: Color(0xFFE8C06A),
    labelImportantUrgent: Color(0xFFD45C3A),
    labelImportantNotUrgent: Color(0xFFC9922E),
    labelUrgentNotImportant: Color(0xFF7A9B4F),
    labelNeither: Color(0xFFB07A4A),
    labelNeedResource: Color(0xFF8A6E48),
    labelDevelopment: Color(0xFF6D63AE),
    labelConsultation: Color(0xFF4C8F7A),
    labelDocumentation: Color(0xFF8D6746),
    labelAcceptance: Color(0xFF5A9465),
    priorityLow: Color(0xFF7A9B4F),
    priorityMedium: Color(0xFFC9922E),
    priorityHigh: Color(0xFFD45C3A),
  ),
  ProjectThemePreset(
    id: 'terracotta',
    name: '陶土',
    seedLight: Color(0xFFB86B4A),
    seedDark: Color(0xFFE0A888),
    labelImportantUrgent: Color(0xFFC24A3A),
    labelImportantNotUrgent: Color(0xFFB86B4A),
    labelUrgentNotImportant: Color(0xFF8B7355),
    labelNeither: Color(0xFF9B6E5A),
    labelNeedResource: Color(0xFF7A6A55),
    labelDevelopment: Color(0xFF6E67A8),
    labelConsultation: Color(0xFF4C867A),
    labelDocumentation: Color(0xFF805B43),
    labelAcceptance: Color(0xFF568C62),
    priorityLow: Color(0xFF7A8B5A),
    priorityMedium: Color(0xFFC9922E),
    priorityHigh: Color(0xFFC24A3A),
  ),
  ProjectThemePreset(
    id: 'mint',
    name: '薄荷',
    seedLight: Color(0xFF2E9E8A),
    seedDark: Color(0xFF6FD4C0),
    labelImportantUrgent: Color(0xFFD45C5C),
    labelImportantNotUrgent: Color(0xFF2E9E8A),
    labelUrgentNotImportant: Color(0xFF5BA88E),
    labelNeither: Color(0xFF5B8FBD),
    labelNeedResource: Color(0xFF8A7A5A),
    labelDevelopment: Color(0xFF5C69AF),
    labelConsultation: Color(0xFF338D7A),
    labelDocumentation: Color(0xFF806A4D),
    labelAcceptance: Color(0xFF4F9A75),
    priorityLow: Color(0xFF5BA88E),
    priorityMedium: Color(0xFFD4A03C),
    priorityHigh: Color(0xFFD45C5C),
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
  final seed =
      brightness == Brightness.dark ? preset.seedDark : preset.seedLight;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamilyFallback: const [
      'Microsoft YaHei',
      'PingFang SC',
      'Noto Sans CJK SC',
    ],
    // 顶部浮动提示：主题色容器底 + 圆角，避免默认底部长黑条
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 3,
      backgroundColor: colorScheme.primaryContainer,
      contentTextStyle: TextStyle(
        color: colorScheme.onPrimaryContainer,
        fontSize: 14,
      ),
      actionTextColor: colorScheme.primary,
      disabledActionTextColor:
          colorScheme.onPrimaryContainer.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      dismissDirection: DismissDirection.up,
      insetPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    ),
  );
}
