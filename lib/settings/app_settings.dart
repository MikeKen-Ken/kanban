import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/kanban/kanban_labels.dart';
import '../features/project/project_list_preferences.dart';

/// 本地应用偏好（不同步到 WebDAV）
class AppSettings {
  const AppSettings({
    required this.dragLongPressMs,
    this.projectSortMode = ProjectSortMode.defaultOrder,
    this.pinnedProjectIds = const [],
    this.projectLastUsedAt = const {},
    this.customLabels = const [],
  });

  /// 拖拽前按压时长（毫秒）。0 表示按下即拖。
  final int dragLongPressMs;

  /// 项目列表排序方式
  final ProjectSortMode projectSortMode;

  /// 置顶项目 id，顺序越靠前显示越靠上
  final List<String> pinnedProjectIds;

  /// 各项目最近打开时间（毫秒时间戳）
  final Map<String, int> projectLastUsedAt;

  /// 用户自定义标签（全局，所有项目共用）
  final List<KanbanLabel> customLabels;

  bool get immediateDrag => dragLongPressMs <= 0;

  Duration get dragDelay => Duration(milliseconds: dragLongPressMs);

  AppSettings copyWith({
    int? dragLongPressMs,
    ProjectSortMode? projectSortMode,
    List<String>? pinnedProjectIds,
    Map<String, int>? projectLastUsedAt,
    List<KanbanLabel>? customLabels,
  }) {
    return AppSettings(
      dragLongPressMs: dragLongPressMs ?? this.dragLongPressMs,
      projectSortMode: projectSortMode ?? this.projectSortMode,
      pinnedProjectIds: pinnedProjectIds ?? this.pinnedProjectIds,
      projectLastUsedAt: projectLastUsedAt ?? this.projectLastUsedAt,
      customLabels: customLabels ?? this.customLabels,
    );
  }

  Map<String, dynamic> toJson() => {
        'dragLongPressMs': dragLongPressMs,
        'projectSortMode': projectSortMode.name,
        'pinnedProjectIds': pinnedProjectIds,
        'projectLastUsedAt': projectLastUsedAt,
        if (customLabels.isNotEmpty)
          'customLabels':
              customLabels.map((label) => label.toJson()).toList(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final lastUsedRaw = json['projectLastUsedAt'] as Map<String, dynamic>?;
    return AppSettings(
      dragLongPressMs: json['dragLongPressMs'] as int? ??
          AppSettings.platformDefault().dragLongPressMs,
      projectSortMode: ProjectSortMode.fromName(
        json['projectSortMode'] as String?,
      ),
      pinnedProjectIds: (json['pinnedProjectIds'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      projectLastUsedAt: lastUsedRaw == null
          ? const {}
          : lastUsedRaw.map(
              (key, value) => MapEntry(key, value as int),
            ),
      customLabels: (json['customLabels'] as List<dynamic>? ?? [])
          .map((e) => KanbanLabel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static bool _platformImmediateDrag() {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return false;
    }
  }

  static AppSettings platformDefault() {
    return AppSettings(
      dragLongPressMs: _platformImmediateDrag() ? 0 : 500,
    );
  }
}

extension AppSettingsRepository on SharedPreferences {
  static const _appSettingsKey = 'app_settings';

  AppSettings loadAppSettings() {
    final raw = getString(_appSettingsKey);
    if (raw == null) return AppSettings.platformDefault();
    return AppSettings.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    await setString(_appSettingsKey, jsonEncode(settings.toJson()));
  }
}
