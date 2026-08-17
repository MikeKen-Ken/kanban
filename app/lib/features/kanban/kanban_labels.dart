import 'package:flutter/material.dart';

import '../project/project_theme.dart';

/// note: 预置标签，卡片上存 key
///
/// ## 预置标签（艾森豪威尔四象限）
/// 使用四字名称直接表达重要性与紧急性：重要紧急、重要不急、次要紧急、次要不急。
/// [KanbanLabel.description] 仍可为辅助说明。
///
/// 工作类型用「咨询」标识非代码交付；无特殊工作类型标签时按一般实施流程处理。
///
/// ## 旧预置兼容
/// 历史 key：`work` / `personal` / `urgent` / `idea` / `documentation` /
/// `development` 不再出现在新预设列表，
/// 但 [findKanbanLabel] 仍可解析为带「（旧）」后缀的友好名，避免静默丢显示。
class KanbanLabel {
  const KanbanLabel({
    required this.key,
    required this.name,
    required this.color,
    this.description,
  });

  final String key;

  /// 短展示名（Chip / 列表主标题）
  final String name;
  final Color color;

  /// 完整说明（Tooltip / 副标题）；自定义标签通常为空
  final String? description;

  int get colorValue => color.toARGB32();

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'color': colorValue,
        if (description != null) 'description': description,
      };

  factory KanbanLabel.fromJson(Map<String, dynamic> json) {
    return KanbanLabel(
      key: json['key'] as String,
      name: json['name'] as String,
      color: Color(json['color'] as int),
      description: json['description'] as String?,
    );
  }
}

/// 当前预置 key（新项目 / 选标签列表）
const kThemePresetLabelKeys = <String>{
  'important_urgent',
  'important_not_urgent',
  'urgent_not_important',
  'not_urgent_not_important',
  'need_resource',
  'consultation',
};

const kPresetLabelKeys = <String>{...kThemePresetLabelKeys};

/// 已废弃但仍可解析显示的旧预置 key
const kLegacyPresetLabelKeys = <String>{
  'work',
  'personal',
  'urgent',
  'idea',
  'documentation',
  'development',
};

/// 按项目主题返回当前预置标签（不含旧 key）
List<KanbanLabel> presetKanbanLabels([String themeId = '']) =>
    [...projectThemeForId(themeId).presetLabels];

/// 旧预置：仅用于已有卡片上的 key 解析，不进入选标签列表
List<KanbanLabel> legacyPresetKanbanLabels([String themeId = '']) =>
    projectThemeForId(themeId).legacyPresetLabels;

/// 合并当前预置与用户自定义标签（不含旧预置）
List<KanbanLabel> allKanbanLabels(
  List<KanbanLabel> custom, {
  String themeId = '',
}) =>
    [...presetKanbanLabels(themeId), ...custom];

/// 选标签 / 编辑用列表：新预设 + 自定义；若 [selectedKeys] 含仅旧预置可解析的 key，则追加以便取消勾选或下拉回显。
List<KanbanLabel> labelsForEditing(
  List<KanbanLabel> custom, {
  String themeId = '',
  Iterable<String> selectedKeys = const [],
}) {
  final base = allKanbanLabels(custom, themeId: themeId);
  final known = {for (final label in base) label.key};
  final extras = <KanbanLabel>[];
  for (final key in selectedKeys) {
    if (key.isEmpty || known.contains(key)) continue;
    final found = findKanbanLabel(key, custom, themeId);
    if (found == null) continue;
    extras.add(found);
    known.add(key);
  }
  if (extras.isEmpty) return base;
  return [...base, ...extras];
}

KanbanLabel? findKanbanLabel(
  String key, [
  List<KanbanLabel> custom = const [],
  String themeId = '',
]) {
  for (final label in custom) {
    if (label.key == key) return label;
  }
  for (final label in presetKanbanLabels(themeId)) {
    if (label.key == key) return label;
  }
  for (final label in legacyPresetKanbanLabels(themeId)) {
    if (label.key == key) return label;
  }
  return null;
}

enum CardPriority {
  none,
  low,
  medium,
  high;

  String get label => switch (this) {
        CardPriority.none => '无',
        CardPriority.low => '低',
        CardPriority.medium => '中',
        CardPriority.high => '高',
      };

  Color color(ColorScheme scheme, {ProjectThemePreset? theme}) {
    final preset = theme ?? projectThemeForId(null);
    return preset.priorityColor(this, scheme);
  }

  static CardPriority fromString(String? value) {
    return CardPriority.values.firstWhere(
      (p) => p.name == value,
      orElse: () => CardPriority.none,
    );
  }

  int get sortWeight => switch (this) {
        CardPriority.high => 4,
        CardPriority.medium => 3,
        CardPriority.low => 2,
        CardPriority.none => 1,
      };
}
