import 'dart:convert';

/// 项目清单中的轻量条目
class ProjectEntry {
  const ProjectEntry({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.revision,
    this.conflictTitle,
    this.conflictDeleted = false,
  });

  final String id;
  final String title;
  final int updatedAt;
  final int revision;

  /// 项目标题冲突时的另一侧标题
  final String? conflictTitle;

  /// 另一侧删除了此项目（删 vs 改）
  final bool conflictDeleted;

  bool get hasConflict => conflictTitle != null || conflictDeleted;

  ProjectEntry copyWith({
    String? id,
    String? title,
    int? updatedAt,
    int? revision,
    Object? conflictTitle = _sentinel,
    bool clearConflictTitle = false,
    bool? conflictDeleted,
    bool clearConflict = false,
  }) {
    return ProjectEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
      conflictTitle: clearConflict || clearConflictTitle
          ? null
          : (conflictTitle == _sentinel
              ? this.conflictTitle
              : conflictTitle as String?),
      conflictDeleted:
          clearConflict ? false : (conflictDeleted ?? this.conflictDeleted),
    );
  }

  static const _sentinel = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt,
        'revision': revision,
        if (conflictTitle != null) 'conflictTitle': conflictTitle,
        if (conflictDeleted) 'conflictDeleted': true,
      };

  factory ProjectEntry.fromJson(Map<String, dynamic> json) {
    return ProjectEntry(
      id: json['id'] as String,
      title: json['title'] as String? ?? '我的看板',
      updatedAt: json['updatedAt'] as int? ?? 0,
      revision: json['revision'] as int? ?? 0,
      conflictTitle: json['conflictTitle'] as String?,
      conflictDeleted: json['conflictDeleted'] as bool? ?? false,
    );
  }
}

/// 多项目清单（同步到 WebDAV 的 projects.json）
class ProjectsManifest {
  const ProjectsManifest({
    required this.projects,
    required this.updatedAt,
    required this.revision,
  });

  final List<ProjectEntry> projects;
  final int updatedAt;
  final int revision;

  ProjectsManifest copyWith({
    List<ProjectEntry>? projects,
    int? updatedAt,
    int? revision,
  }) {
    return ProjectsManifest(
      projects: projects ?? this.projects,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 3,
        'projects': projects.map((p) => p.toJson()).toList(),
        'updatedAt': updatedAt,
        'revision': revision,
      };

  factory ProjectsManifest.fromJson(Map<String, dynamic> json) {
    return ProjectsManifest(
      projects: (json['projects'] as List<dynamic>? ?? [])
          .map((e) => ProjectEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      updatedAt: json['updatedAt'] as int? ?? 0,
      revision: json['revision'] as int? ?? 0,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ProjectsManifest.fromJsonString(String source) {
    return ProjectsManifest.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  /// note: 兼容旧调用；完整并集请用 sync_conflict.mergeManifests
  ProjectsManifest mergeWith(ProjectsManifest remote) {
    if (remote.revision > revision) return remote;
    if (remote.revision < revision) return this;
    return remote.updatedAt >= updatedAt ? remote : this;
  }

  ProjectsManifest bump() {
    return copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      revision: revision + 1,
    );
  }

  ProjectEntry? findById(String id) {
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }
}
