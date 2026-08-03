import '../activity/activity_models.dart';
import '../templates/card_template.dart';
import '../views/saved_view.dart';

/// 跨项目同步的自定义标签定义。
class SharedLabel {
  const SharedLabel({
    required this.id,
    required this.name,
    required this.colorValue,
    this.updatedAt = 0,
  });

  final String id;
  final String name;
  final int colorValue;
  final int updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorValue,
        'updatedAt': updatedAt,
      };

  factory SharedLabel.fromJson(Map<String, dynamic> json) {
    return SharedLabel(
      id: _readString(json['id'] ?? json['key']),
      name: _readString(json['name'], fallback: '未命名标签'),
      colorValue: _readInt(json['color'] ?? json['colorValue']),
      updatedAt: _readInt(json['updatedAt']),
    );
  }
}

/// 工作区根级共享用户内容。
///
/// revision/updatedAt 同时为 0 表示旧端未提供共享内容文件。真正保存过的空内容
/// 必须提升 revision，以便同步合并区分“全部删除”和“缺文件”。
class SharedContent {
  const SharedContent({
    this.labels = const [],
    this.savedViews = const [],
    this.cardTemplates = const [],
    this.activityByProject = const {},
    this.updatedAt = 0,
    this.revision = 0,
  });

  static const empty = SharedContent();

  final List<SharedLabel> labels;
  final List<SavedView> savedViews;
  final List<CardTemplate> cardTemplates;
  final Map<String, ActivityLog> activityByProject;
  final int updatedAt;
  final int revision;

  bool get isUninitialized =>
      revision == 0 &&
      updatedAt == 0 &&
      labels.isEmpty &&
      savedViews.isEmpty &&
      cardTemplates.isEmpty &&
      activityByProject.isEmpty;

  SharedContent copyWith({
    List<SharedLabel>? labels,
    List<SavedView>? savedViews,
    List<CardTemplate>? cardTemplates,
    Map<String, ActivityLog>? activityByProject,
    int? updatedAt,
    int? revision,
  }) {
    return SharedContent(
      labels: labels ?? this.labels,
      savedViews: savedViews ?? this.savedViews,
      cardTemplates: cardTemplates ?? this.cardTemplates,
      activityByProject: activityByProject ?? this.activityByProject,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
    );
  }

  SharedContent bump([int? now]) => copyWith(
        updatedAt: now ?? DateTime.now().millisecondsSinceEpoch,
        revision: revision + 1,
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'labels': labels.map((item) => item.toJson()).toList(),
        'savedViews': savedViews.map((item) => item.toJson()).toList(),
        'cardTemplates': cardTemplates.map((item) => item.toJson()).toList(),
        'activityByProject': activityByProject.map(
          (projectId, log) => MapEntry(projectId, log.toJson()),
        ),
        'updatedAt': updatedAt,
        'revision': revision,
      };

  factory SharedContent.fromJson(Map<String, dynamic> json) {
    return SharedContent(
      labels: _readMapList(json['labels'])
          .map(SharedLabel.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      savedViews: _readMapList(json['savedViews'])
          .map(SavedView.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      cardTemplates: _readMapList(json['cardTemplates'] ?? json['templates'])
          .map(CardTemplate.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      activityByProject: _readMap(json['activityByProject']).map(
        (projectId, value) => MapEntry(
          projectId,
          value is Map
              ? ActivityLog.fromJson(Map<String, dynamic>.from(value))
              : const ActivityLog(),
        ),
      ),
      updatedAt: _readInt(json['updatedAt']),
      revision: _readInt(json['revision']),
    );
  }
}

List<Map<String, dynamic>> _readMapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

Map<String, dynamic> _readMap(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}

String _readString(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

int _readInt(Object? value) => value is num ? value.toInt() : 0;
