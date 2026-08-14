import 'dart:convert';

import '../automations/automation_models.dart';
import '../kanban/column_card_preferences.dart';
import '../kanban/swimlane.dart';
import '../wallpapers/wallpaper_models.dart';

/// 单个项目的偏好设置（随项目数据同步到 WebDAV）
class ProjectSettings {
  const ProjectSettings({
    this.doneColumnName = '已完成',
    this.themeId = '',
    this.backgroundAttachmentId = '',
    this.wallpaperIds = const [],
    this.wallpaperActiveId = '',
    this.wallpaperPlaybackMode = WallpaperPlaybackMode.random,
    this.wallpaperIntervalSeconds = defaultWallpaperIntervalSeconds,
    this.backgroundOverlayOpacity = defaultBackgroundOverlayOpacity,
    this.cardSurfaceOpacity = defaultCardSurfaceOpacity,
    this.columnPreferences = const {},
    this.columnWipLimits = const {},
    this.swimlaneMode = SwimlaneMode.none,
    this.automationRules = const [],
    this.updatedAt = 0,
    this.revision = 0,
    this.conflictSide,
  });

  /// 已完成列的显示名称，也用于识别完成列
  final String doneColumnName;

  /// 项目主题 id，空字符串表示使用默认主题
  final String themeId;

  /// 看板背景图附件 id，空字符串表示无自定义背景
  final String backgroundAttachmentId;

  /// 当前项目选择的工作区壁纸 id；固定模式通常只有一项。
  final List<String> wallpaperIds;

  /// 随机轮播时当前展示的壁纸 id；空表示使用 [wallpaperIds] 首项。
  final String wallpaperActiveId;

  final WallpaperPlaybackMode wallpaperPlaybackMode;
  final int wallpaperIntervalSeconds;

  /// 背景图上的半透明遮罩强度（0–[maxBackgroundOverlayOpacity]）
  final double backgroundOverlayOpacity;

  /// 看板卡片表面不透明度（[minCardSurfaceOpacity]–1）；低于 1 时透过卡片看到壁纸
  final double cardSurfaceOpacity;

  /// 各列卡片展示偏好（排序、置顶）
  final Map<String, ColumnCardPreferences> columnPreferences;

  /// 各列建议的在制品上限；未配置或小于 1 表示不限
  final Map<String, int> columnWipLimits;

  /// 看板泳道分组方式
  final SwimlaneMode swimlaneMode;

  /// 本地自动化规则
  final List<AutomationRule> automationRules;
  final int updatedAt;
  final int revision;

  /// 设置冲突时另一侧完整快照
  final ProjectSettings? conflictSide;

  bool get hasConflict => conflictSide != null;

  bool get hasBackgroundImage =>
      wallpaperIds.isNotEmpty || backgroundAttachmentId.isNotEmpty;

  List<String> get effectiveWallpaperIds => wallpaperIds.isNotEmpty
      ? wallpaperIds
      : (backgroundAttachmentId.isEmpty
          ? const <String>[]
          : <String>[backgroundAttachmentId]);

  String activeWallpaperIdFor(List<String> displayableIds) {
    if (displayableIds.isEmpty) return '';
    if (wallpaperActiveId.isNotEmpty &&
        displayableIds.contains(wallpaperActiveId)) {
      return wallpaperActiveId;
    }
    return displayableIds.first;
  }

  static const defaultDoneColumnName = '已完成';
  static const defaultBackgroundOverlayOpacity = 0.4;
  static const maxBackgroundOverlayOpacity = 0.7;
  static const defaultCardSurfaceOpacity = 1.0;
  static const minCardSurfaceOpacity = 0.35;

  /// 新项目默认每 10 秒从工作区壁纸库随机轮播；库为空时保持纯色。
  static ProjectSettings defaultsForNewProject(List<String> libraryWallpaperIds) {
    final ids = libraryWallpaperIds
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    return ProjectSettings(
      wallpaperIds: ids,
      wallpaperActiveId: ids.isEmpty ? '' : ids.first,
      backgroundAttachmentId: ids.isEmpty ? '' : ids.first,
      wallpaperPlaybackMode: WallpaperPlaybackMode.random,
    );
  }

  static const defaultWallpaperIntervalSeconds = 10;
  static const legacyWallpaperIntervalSeconds = 60;
  static const minWallpaperIntervalSeconds = 10;
  static const maxWallpaperIntervalSeconds = 86400;

  ProjectSettings copyWith({
    String? doneColumnName,
    String? themeId,
    String? backgroundAttachmentId,
    List<String>? wallpaperIds,
    String? wallpaperActiveId,
    WallpaperPlaybackMode? wallpaperPlaybackMode,
    int? wallpaperIntervalSeconds,
    double? backgroundOverlayOpacity,
    double? cardSurfaceOpacity,
    Map<String, ColumnCardPreferences>? columnPreferences,
    Map<String, int>? columnWipLimits,
    SwimlaneMode? swimlaneMode,
    List<AutomationRule>? automationRules,
    int? updatedAt,
    int? revision,
    Object? conflictSide = _sentinel,
    bool clearConflictSide = false,
  }) {
    return ProjectSettings(
      doneColumnName: doneColumnName ?? this.doneColumnName,
      themeId: themeId ?? this.themeId,
      backgroundAttachmentId:
          backgroundAttachmentId ?? this.backgroundAttachmentId,
      wallpaperIds: wallpaperIds ?? this.wallpaperIds,
      wallpaperActiveId: wallpaperActiveId ?? this.wallpaperActiveId,
      wallpaperPlaybackMode:
          wallpaperPlaybackMode ?? this.wallpaperPlaybackMode,
      wallpaperIntervalSeconds: wallpaperIntervalSeconds == null
          ? this.wallpaperIntervalSeconds
          : clampWallpaperIntervalSeconds(wallpaperIntervalSeconds),
      backgroundOverlayOpacity:
          backgroundOverlayOpacity ?? this.backgroundOverlayOpacity,
      cardSurfaceOpacity: cardSurfaceOpacity ?? this.cardSurfaceOpacity,
      columnPreferences: columnPreferences ?? this.columnPreferences,
      columnWipLimits: columnWipLimits ?? this.columnWipLimits,
      swimlaneMode: swimlaneMode ?? this.swimlaneMode,
      automationRules: automationRules ?? this.automationRules,
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

  static double clampOverlayOpacity(double value) =>
      value.clamp(0.0, maxBackgroundOverlayOpacity).toDouble();

  static double clampCardSurfaceOpacity(double value) =>
      value.clamp(minCardSurfaceOpacity, defaultCardSurfaceOpacity).toDouble();

  static int clampWallpaperIntervalSeconds(int value) => value
      .clamp(minWallpaperIntervalSeconds, maxWallpaperIntervalSeconds)
      .toInt();

  Map<String, dynamic> toJson({bool includeConflict = true}) {
    final map = <String, dynamic>{
      'doneColumnName': doneColumnName,
      if (themeId.isNotEmpty) 'themeId': themeId,
      if (backgroundAttachmentId.isNotEmpty)
        'backgroundAttachmentId': backgroundAttachmentId,
      if (wallpaperIds.isNotEmpty) 'wallpaperIds': wallpaperIds,
      // 当前轮播位置只是本机展示状态，不属于跨设备同步的数据。
      if (wallpaperPlaybackMode != WallpaperPlaybackMode.fixed)
        'wallpaperPlaybackMode': wallpaperPlaybackMode.name,
      if (wallpaperIntervalSeconds != defaultWallpaperIntervalSeconds)
        'wallpaperIntervalSeconds': wallpaperIntervalSeconds,
      if (backgroundOverlayOpacity != defaultBackgroundOverlayOpacity)
        'backgroundOverlayOpacity': backgroundOverlayOpacity,
      if (cardSurfaceOpacity != defaultCardSurfaceOpacity)
        'cardSurfaceOpacity': cardSurfaceOpacity,
      if (columnPreferences.isNotEmpty)
        'columnPreferences': columnPreferences.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      if (columnWipLimits.isNotEmpty) 'columnWipLimits': columnWipLimits,
      if (swimlaneMode != SwimlaneMode.none) 'swimlaneMode': swimlaneMode.name,
      if (automationRules.isNotEmpty)
        'automationRules': automationRules.map((r) => r.toJson()).toList(),
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
    final overlayRaw = json['backgroundOverlayOpacity'];
    final overlay = overlayRaw is num
        ? clampOverlayOpacity(overlayRaw.toDouble())
        : defaultBackgroundOverlayOpacity;
    final cardOpacityRaw = json['cardSurfaceOpacity'];
    final cardOpacity = cardOpacityRaw is num
        ? clampCardSurfaceOpacity(cardOpacityRaw.toDouble())
        : defaultCardSurfaceOpacity;
    final rulesRaw = json['automationRules'] as List<dynamic>?;
    final wallpaperMode = WallpaperPlaybackModeX.fromString(
      json['wallpaperPlaybackMode'] as String?,
    );
    final intervalRaw = (json['wallpaperIntervalSeconds'] as num?)?.toInt();
    return ProjectSettings(
      doneColumnName:
          json['doneColumnName'] as String? ?? defaultDoneColumnName,
      themeId: json['themeId'] as String? ?? '',
      backgroundAttachmentId: json['backgroundAttachmentId'] as String? ?? '',
      wallpaperIds: (json['wallpaperIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false),
      wallpaperActiveId: json['wallpaperActiveId'] as String? ?? '',
      wallpaperPlaybackMode: wallpaperMode,
      wallpaperIntervalSeconds: clampWallpaperIntervalSeconds(
        intervalRaw ??
            (wallpaperMode == WallpaperPlaybackMode.random
                ? defaultWallpaperIntervalSeconds
                : legacyWallpaperIntervalSeconds),
      ),
      backgroundOverlayOpacity: overlay,
      cardSurfaceOpacity: cardOpacity,
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
      swimlaneMode: SwimlaneModeX.fromString(json['swimlaneMode'] as String?),
      automationRules: rulesRaw == null
          ? const []
          : rulesRaw
              .map((e) => AutomationRule.fromJson(e as Map<String, dynamic>))
              .toList(),
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
