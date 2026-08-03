import 'dart:convert';

import '../kanban/column_card_preferences.dart';

/// 单个项目的偏好设置（随项目数据同步到 WebDAV）
class ProjectSettings {
  const ProjectSettings({
    this.doneColumnName = '已完成',
    this.themeId = '',
    this.columnPreferences = const {},
    this.columnWipLimits = const {},
    this.updatedAt = 0,
    this.revision = 0,
    this.conflictSide,
  });

  /// 已完成列的显示名称，也用于识别完成列
  final String doneColumnName;

  /// 项目主题 id，空字符串表示使用默认主题
  final String themeId;

  /// 各列卡片展示偏好（排序、置顶）
  final Map<String, ColumnCardPreferences> columnPreferences;

  /// 各列建议的在制品上限；未配置或小于 1 表示不限
  final Map<String, int> columnWipLimits;
  final int updatedAt;
  final int revision;

  /// 设置冲突时另一侧完整快照
  final ProjectSettings? conflictSide;

  bool get hasConflict => conflictSide != null;

  static const defaultDoneColumnName = '已完成';

  ProjectSettings copyWith({
    String? doneColumnName,
    String? themeId,
    Map<String, ColumnCardPreferences>? columnPreferences,
    Map<String, int>? columnWipLimits,
    int? updatedAt,
    int? revision,
    Object? conflictSide = _sentinel,
    bool clearConflictSide = false,
  }) {
    return ProjectSettings(
      doneColumnName: doneColumnName ?? this.doneColumnName,
      themeId: themeId ?? this.themeId,
      columnPreferences: columnPreferences ?? this.columnPreferences,
      columnWipLimits: columnWipLimits ?? this.columnWipLimits,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
      conflictSide: clearConflictSide
          ? null
          : (conflictSide == _sentinel
              ? this.conflictSide
              : conflictSide as ProjectSettings?),
    );
  }

  static const _sentinel = Object();

  ColumnCardPreferences columnPreferencesFor(String columnId) =>
      columnPreferences[columnId] ?? const ColumnCardPreferences();

  int? wipLimitFor(String columnId) {
    final value = columnWipLimits[columnId];
    return value == null || value < 1 ? null : value;
  }

  Map<String, dynamic> toJson({bool includeConflict = true}) {
    final map = <String, dynamic>{
      'doneColumnName': doneColumnName,
      if (themeId.isNotEmpty) 'themeId': themeId,
      if (columnPreferences.isNotEmpty)
        'columnPreferences': columnPreferences.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      if (columnWipLimits.isNotEmpty) 'columnWipLimits': columnWipLimits,
      'updatedAt': updatedAt,
      'revision': revision,
    };
    if (includeConflict && conflictSide != null) {
      map['conflictSide'] = conflictSide!.toJson(includeConflict: false);
    }
    return map;
  }

  factory ProjectSettings.fromJson(Map<String, dynamic> json) {
    final prefsRaw = json['columnPreferences'] as Map<String, dynamic>?;
    final wipRaw = json['columnWipLimits'] as Map<String, dynamic>?;
    final sideRaw = json['conflictSide'] as Map<String, dynamic>?;
    return ProjectSettings(
      doneColumnName:
          json['doneColumnName'] as String? ?? defaultDoneColumnName,
      themeId: json['themeId'] as String? ?? '',
      columnPreferences: prefsRaw == null
          ? const {}
          : prefsRaw.map(
              (key, value) => MapEntry(
                key,
                ColumnCardPreferences.fromJson(
                  value as Map<String, dynamic>,
                ),
              ),
            ),
      columnWipLimits: wipRaw == null
          ? const {}
          : wipRaw.map((key, value) => MapEntry(key, value as int)),
      updatedAt: json['updatedAt'] as int? ?? 0,
      revision: json['revision'] as int? ?? 0,
      conflictSide: sideRaw == null ? null : ProjectSettings.fromJson(sideRaw),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ProjectSettings.fromJsonString(String source) {
    return ProjectSettings.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  /// note: 兼容旧调用；字段级合并请用 sync_conflict.mergeSettings
  ProjectSettings mergeWith(ProjectSettings remote) {
    if (remote.revision > revision) return remote;
    if (remote.revision < revision) return this;
    return remote.updatedAt >= updatedAt ? remote : this;
  }

  ProjectSettings bump() {
    return copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      revision: revision + 1,
    );
  }
}
