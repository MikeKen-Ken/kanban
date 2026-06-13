import 'dart:convert';

import '../kanban/kanban_labels.dart';
import '../project/project_settings.dart';
import '../project/projects_manifest.dart';
import '../../models/kanban_models.dart';

enum TrashItemType {
  card,
  column,
  project,
  customLabel;

  String get label => switch (this) {
        TrashItemType.card => '卡片',
        TrashItemType.column => '列',
        TrashItemType.project => '项目',
        TrashItemType.customLabel => '标签',
      };

  static TrashItemType fromName(String? name) {
    return TrashItemType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => TrashItemType.card,
    );
  }
}

/// 回收站中的单条记录
class TrashItem {
  const TrashItem({
    required this.id,
    required this.type,
    required this.deletedAt,
    required this.displayName,
    required this.payload,
    this.projectId,
    this.projectTitle,
    this.columnId,
    this.columnTitle,
  });

  final String id;
  final TrashItemType type;
  final int deletedAt;
  final String displayName;
  final String? projectId;
  final String? projectTitle;
  final String? columnId;
  final String? columnTitle;
  final Map<String, dynamic> payload;

  TrashItem copyWith({
    String? id,
    TrashItemType? type,
    int? deletedAt,
    String? displayName,
    String? projectId,
    String? projectTitle,
    String? columnId,
    String? columnTitle,
    Map<String, dynamic>? payload,
  }) {
    return TrashItem(
      id: id ?? this.id,
      type: type ?? this.type,
      deletedAt: deletedAt ?? this.deletedAt,
      displayName: displayName ?? this.displayName,
      projectId: projectId ?? this.projectId,
      projectTitle: projectTitle ?? this.projectTitle,
      columnId: columnId ?? this.columnId,
      columnTitle: columnTitle ?? this.columnTitle,
      payload: payload ?? this.payload,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'deletedAt': deletedAt,
        'displayName': displayName,
        if (projectId != null) 'projectId': projectId,
        if (projectTitle != null) 'projectTitle': projectTitle,
        if (columnId != null) 'columnId': columnId,
        if (columnTitle != null) 'columnTitle': columnTitle,
        'payload': payload,
      };

  factory TrashItem.fromJson(Map<String, dynamic> json) {
    return TrashItem(
      id: json['id'] as String,
      type: TrashItemType.fromName(json['type'] as String?),
      deletedAt: json['deletedAt'] as int? ?? 0,
      displayName: json['displayName'] as String? ?? '',
      projectId: json['projectId'] as String?,
      projectTitle: json['projectTitle'] as String?,
      columnId: json['columnId'] as String?,
      columnTitle: json['columnTitle'] as String?,
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
    );
  }

  static TrashItem forCard({
    required String trashId,
    required int deletedAt,
    required String projectId,
    required String projectTitle,
    required String columnId,
    required String columnTitle,
    required KanbanCard card,
  }) {
    return TrashItem(
      id: trashId,
      type: TrashItemType.card,
      deletedAt: deletedAt,
      displayName: card.title,
      projectId: projectId,
      projectTitle: projectTitle,
      columnId: columnId,
      columnTitle: columnTitle,
      payload: {
        'card': card.toJson(),
      },
    );
  }

  static TrashItem forColumn({
    required String trashId,
    required int deletedAt,
    required String projectId,
    required String projectTitle,
    required KanbanColumn column,
  }) {
    return TrashItem(
      id: trashId,
      type: TrashItemType.column,
      deletedAt: deletedAt,
      displayName: column.title,
      projectId: projectId,
      projectTitle: projectTitle,
      columnId: column.id,
      columnTitle: column.title,
      payload: {
        'column': column.toJson(),
      },
    );
  }

  static TrashItem forProject({
    required String trashId,
    required int deletedAt,
    required ProjectEntry entry,
    required KanbanBoard board,
    required ProjectSettings settings,
    required TrashBin projectTrash,
  }) {
    return TrashItem(
      id: trashId,
      type: TrashItemType.project,
      deletedAt: deletedAt,
      displayName: entry.title,
      projectId: entry.id,
      projectTitle: entry.title,
      payload: {
        'entry': entry.toJson(),
        'board': board.toMetadataJson(),
        'columns': board.columns.map((c) => c.toJson()).toList(),
        'settings': settings.toJson(),
        'projectTrash': projectTrash.toJson(),
      },
    );
  }

  static TrashItem forCustomLabel({
    required String trashId,
    required int deletedAt,
    required KanbanLabel label,
  }) {
    return TrashItem(
      id: trashId,
      type: TrashItemType.customLabel,
      deletedAt: deletedAt,
      displayName: label.name,
      payload: {
        'label': label.toJson(),
      },
    );
  }

  KanbanCard? get cardPayload {
    if (type != TrashItemType.card) return null;
    final raw = payload['card'] as Map<String, dynamic>?;
    return raw == null ? null : KanbanCard.fromJson(raw);
  }

  KanbanColumn? get columnPayload {
    if (type != TrashItemType.column) return null;
    final raw = payload['column'] as Map<String, dynamic>?;
    return raw == null ? null : KanbanColumn.fromJson(raw);
  }

  ({ProjectEntry entry, KanbanBoard board, ProjectSettings settings, TrashBin projectTrash})?
      get projectPayload {
    if (type != TrashItemType.project) return null;
    final entryRaw = payload['entry'] as Map<String, dynamic>?;
    final boardMeta = payload['board'] as Map<String, dynamic>?;
    final columnsRaw = payload['columns'] as List<dynamic>?;
    final settingsRaw = payload['settings'] as Map<String, dynamic>?;
    if (entryRaw == null || boardMeta == null || columnsRaw == null) return null;

    final columns = columnsRaw
        .map((e) => KanbanColumn.fromJson(e as Map<String, dynamic>))
        .toList();
    final board = KanbanBoard.fromMetadataJson(boardMeta, columns);
    final settings = settingsRaw == null
        ? const ProjectSettings()
        : ProjectSettings.fromJson(settingsRaw);
    final trashRaw = payload['projectTrash'] as Map<String, dynamic>?;
    final projectTrash = trashRaw == null
        ? TrashBin.empty
        : TrashBin.fromJson(trashRaw);

    return (
      entry: ProjectEntry.fromJson(entryRaw),
      board: board,
      settings: settings,
      projectTrash: projectTrash,
    );
  }

  KanbanLabel? get labelPayload {
    if (type != TrashItemType.customLabel) return null;
    final raw = payload['label'] as Map<String, dynamic>?;
    return raw == null ? null : KanbanLabel.fromJson(raw);
  }
}

/// 回收站容器（按项目或应用级）
class TrashBin {
  const TrashBin({
    required this.items,
    required this.updatedAt,
    required this.revision,
  });

  final List<TrashItem> items;
  final int updatedAt;
  final int revision;

  static const empty = TrashBin(items: [], updatedAt: 0, revision: 0);

  bool get isEmpty => items.isEmpty;

  TrashBin copyWith({
    List<TrashItem>? items,
    int? updatedAt,
    int? revision,
  }) {
    return TrashBin(
      items: items ?? this.items,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
    );
  }

  TrashBin bump() {
    return copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      revision: revision + 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'items': items.map((item) => item.toJson()).toList(),
        'updatedAt': updatedAt,
        'revision': revision,
      };

  factory TrashBin.fromJson(Map<String, dynamic> json) {
    return TrashBin(
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => TrashItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      updatedAt: json['updatedAt'] as int? ?? 0,
      revision: json['revision'] as int? ?? 0,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory TrashBin.fromJsonString(String source) {
    return TrashBin.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }

  /// note: 合并策略 — 按回收记录 id 去重合并，修订号更高者优先
  TrashBin mergeWith(TrashBin remote) {
    if (remote.revision > revision) {
      return _mergeItems(remote, this);
    }
    if (remote.revision < revision) {
      return _mergeItems(this, remote);
    }
    if (remote.updatedAt >= updatedAt) {
      return _mergeItems(remote, this);
    }
    return _mergeItems(this, remote);
  }

  static TrashBin _mergeItems(TrashBin primary, TrashBin secondary) {
    final byId = <String, TrashItem>{
      for (final item in secondary.items) item.id: item,
    };
    for (final item in primary.items) {
      byId[item.id] = item;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return TrashBin(
      items: merged,
      updatedAt: primary.updatedAt > secondary.updatedAt
          ? primary.updatedAt
          : secondary.updatedAt,
      revision: primary.revision > secondary.revision
          ? primary.revision
          : secondary.revision,
    );
  }
}
