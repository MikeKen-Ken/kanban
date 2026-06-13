import 'package:flutter/material.dart';

import '../project/project_theme.dart';

/// note: 预置标签，卡片上存 key
class KanbanLabel {
  const KanbanLabel({required this.key, required this.name, required this.color});

  final String key;
  final String name;
  final Color color;

  int get colorValue => color.toARGB32();

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'color': colorValue,
      };

  factory KanbanLabel.fromJson(Map<String, dynamic> json) {
    return KanbanLabel(
      key: json['key'] as String,
      name: json['name'] as String,
      color: Color(json['color'] as int),
    );
  }
}

/// 按项目主题返回预置标签
List<KanbanLabel> presetKanbanLabels([String themeId = '']) =>
    projectThemeForId(themeId).presetLabels;

/// 合并预置与用户自定义标签
List<KanbanLabel> allKanbanLabels(
  List<KanbanLabel> custom, {
  String themeId = '',
}) => [...presetKanbanLabels(themeId), ...custom];

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
