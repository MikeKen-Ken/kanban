import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/kanban/kanban_labels.dart';
import '../features/mcp/mcp_constants.dart';
import '../features/project/project_list_preferences.dart';

/// 本地应用偏好（不同步到 WebDAV）
class AppSettings {
  const AppSettings({
    required this.dragLongPressMs,
    this.themeMode = ThemeMode.system,
    this.hasCompletedOnboarding = false,
    this.hasRequestedNotificationPermission = false,
    this.projectSortMode = ProjectSortMode.defaultOrder,
    this.pinnedProjectIds = const [],
    this.projectLastUsedAt = const {},
    this.customLabels = const [],
    this.mcpEnabled = false,
    this.mcpPort = McpConstants.defaultPort,
  });

  /// 拖拽前按压时长（毫秒）。0 表示按下即拖。
  final int dragLongPressMs;

  /// 设备本机的明暗模式偏好
  final ThemeMode themeMode;

  /// 是否已完成首次使用引导
  final bool hasCompletedOnboarding;

  /// 是否已在本机请求过通知权限（仅 Android 有意义）
  final bool hasRequestedNotificationPermission;

  /// 项目列表排序方式
  final ProjectSortMode projectSortMode;

  /// 置顶项目 id，顺序越靠前显示越靠上
  final List<String> pinnedProjectIds;

  /// 各项目最近打开时间（毫秒时间戳）
  final Map<String, int> projectLastUsedAt;

  /// 用户自定义标签（全局，所有项目共用）
  final List<KanbanLabel> customLabels;

  /// 是否启用 Windows 内嵌 MCP（仅本机）
  final bool mcpEnabled;

  /// MCP 监听端口（仅本机）
  final int mcpPort;

  /// 0ms：按下并移动即拖
  bool get immediateDrag => dragLongPressMs <= 0;

  Duration get dragDelay => Duration(milliseconds: dragLongPressMs);

  AppSettings copyWith({
    int? dragLongPressMs,
    ThemeMode? themeMode,
    bool? hasCompletedOnboarding,
    bool? hasRequestedNotificationPermission,
    ProjectSortMode? projectSortMode,
    List<String>? pinnedProjectIds,
    Map<String, int>? projectLastUsedAt,
    List<KanbanLabel>? customLabels,
    bool? mcpEnabled,
    int? mcpPort,
  }) {
    return AppSettings(
      dragLongPressMs: dragLongPressMs ?? this.dragLongPressMs,
      themeMode: themeMode ?? this.themeMode,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      hasRequestedNotificationPermission:
          hasRequestedNotificationPermission ??
              this.hasRequestedNotificationPermission,
      projectSortMode: projectSortMode ?? this.projectSortMode,
      pinnedProjectIds: pinnedProjectIds ?? this.pinnedProjectIds,
      projectLastUsedAt: projectLastUsedAt ?? this.projectLastUsedAt,
      customLabels: customLabels ?? this.customLabels,
      mcpEnabled: mcpEnabled ?? this.mcpEnabled,
      mcpPort: mcpPort ?? this.mcpPort,
    );
  }

  Map<String, dynamic> toJson() => {
        'dragLongPressMs': dragLongPressMs,
        'themeMode': themeMode.name,
        'hasCompletedOnboarding': hasCompletedOnboarding,
        'hasRequestedNotificationPermission':
            hasRequestedNotificationPermission,
        'projectSortMode': projectSortMode.name,
        'pinnedProjectIds': pinnedProjectIds,
        'projectLastUsedAt': projectLastUsedAt,
        if (customLabels.isNotEmpty)
          'customLabels': customLabels.map((label) => label.toJson()).toList(),
        'mcpEnabled': mcpEnabled,
        'mcpPort': mcpPort,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.platformDefault();
    final lastUsedRaw = json['projectLastUsedAt'] as Map<String, dynamic>?;
    final port = json['mcpPort'] as int? ?? defaults.mcpPort;
    return AppSettings(
      dragLongPressMs: json['dragLongPressMs'] as int? ??
          defaults.dragLongPressMs,
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == json['themeMode'],
        orElse: () => ThemeMode.system,
      ),
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
      hasRequestedNotificationPermission:
          json['hasRequestedNotificationPermission'] as bool? ?? false,
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
      mcpEnabled: json['mcpEnabled'] as bool? ?? defaults.mcpEnabled,
      mcpPort: port < 1 || port > 65535 ? defaults.mcpPort : port,
    );
  }

  static bool _platformMcpEnabledDefault() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows;
  }

  static AppSettings platformDefault() {
    return AppSettings(
      dragLongPressMs: 200,
      mcpEnabled: _platformMcpEnabledDefault(),
      mcpPort: McpConstants.defaultPort,
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
