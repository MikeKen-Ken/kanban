import 'dart:convert';

/// 单个项目的偏好设置（随项目数据同步到 WebDAV）
class ProjectSettings {
  const ProjectSettings({
    this.doneColumnName = '已完成',
    this.updatedAt = 0,
    this.revision = 0,
  });

  /// 已完成列的显示名称，也用于识别完成列
  final String doneColumnName;
  final int updatedAt;
  final int revision;

  static const defaultDoneColumnName = '已完成';

  ProjectSettings copyWith({
    String? doneColumnName,
    int? updatedAt,
    int? revision,
  }) {
    return ProjectSettings(
      doneColumnName: doneColumnName ?? this.doneColumnName,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
    );
  }

  Map<String, dynamic> toJson() => {
        'doneColumnName': doneColumnName,
        'updatedAt': updatedAt,
        'revision': revision,
      };

  factory ProjectSettings.fromJson(Map<String, dynamic> json) {
    return ProjectSettings(
      doneColumnName:
          json['doneColumnName'] as String? ?? defaultDoneColumnName,
      updatedAt: json['updatedAt'] as int? ?? 0,
      revision: json['revision'] as int? ?? 0,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ProjectSettings.fromJsonString(String source) {
    return ProjectSettings.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  /// note: 合并策略 — 修订号更高者优先；相同则时间戳更新者优先
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
