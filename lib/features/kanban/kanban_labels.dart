import 'package:flutter/material.dart';

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

const kKanbanLabels = <KanbanLabel>[
  KanbanLabel(key: 'work', name: '工作', color: Color(0xFF4F6BED)),
  KanbanLabel(key: 'personal', name: '个人', color: Color(0xFF2E9E6A)),
  KanbanLabel(key: 'urgent', name: '紧急', color: Color(0xFFE05252)),
  KanbanLabel(key: 'idea', name: '想法', color: Color(0xFF9B59B6)),
];

/// 合并预置与用户自定义标签
List<KanbanLabel> allKanbanLabels(List<KanbanLabel> custom) =>
    [...kKanbanLabels, ...custom];

KanbanLabel? findKanbanLabel(String key, [List<KanbanLabel> custom = const []]) {
  for (final label in custom) {
    if (label.key == key) return label;
  }
  for (final label in kKanbanLabels) {
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

  Color color(ColorScheme scheme) => switch (this) {
        CardPriority.none => scheme.outline,
        CardPriority.low => Colors.green,
        CardPriority.medium => Colors.orange,
        CardPriority.high => Colors.red,
      };

  static CardPriority fromString(String? value) {
    return CardPriority.values.firstWhere(
      (p) => p.name == value,
      orElse: () => CardPriority.none,
    );
  }
}
