import 'dart:convert';

import '../activity/activity_models.dart';
import '../shared_content/shared_content.dart';
import '../templates/card_template.dart';
import '../views/saved_view.dart';

typedef _IdOf<T> = String Function(T value);
typedef _UpdatedAtOf<T> = int Function(T value);
typedef _ToJson<T> = Map<String, dynamic> Function(T value);

bool _jsonEqual<T>(T a, T b, _ToJson<T> toJson) =>
    jsonEncode(toJson(a)) == jsonEncode(toJson(b));

List<T> _mergeEntitiesById<T>({
  required List<T> local,
  required List<T> remote,
  required List<T> base,
  required _IdOf<T> idOf,
  required _UpdatedAtOf<T> updatedAtOf,
  required _ToJson<T> toJson,
}) {
  final localById = {for (final item in local) idOf(item): item};
  final remoteById = {for (final item in remote) idOf(item): item};
  final baseById = {for (final item in base) idOf(item): item};
  final allIds = <String>{
    ...localById.keys,
    ...remoteById.keys,
    ...baseById.keys,
  };
  final merged = <T>[];

  for (final id in allIds) {
    final localItem = localById[id];
    final remoteItem = remoteById[id];
    final baseItem = baseById[id];

    if (localItem != null && remoteItem != null) {
      if (_jsonEqual(localItem, remoteItem, toJson)) {
        merged.add(localItem);
        continue;
      }
      if (baseItem != null) {
        final localChanged = !_jsonEqual(localItem, baseItem, toJson);
        final remoteChanged = !_jsonEqual(remoteItem, baseItem, toJson);
        if (localChanged && !remoteChanged) {
          merged.add(localItem);
          continue;
        }
        if (!localChanged && remoteChanged) {
          merged.add(remoteItem);
          continue;
        }
      }
      merged.add(
        updatedAtOf(localItem) >= updatedAtOf(remoteItem)
            ? localItem
            : remoteItem,
      );
      continue;
    }

    if (localItem != null) {
      // 远端删除：本地相对 base 有修改时保留，否则传播删除。
      if (baseItem == null || !_jsonEqual(localItem, baseItem, toJson)) {
        merged.add(localItem);
      }
      continue;
    }

    if (remoteItem != null) {
      // 本地删除：远端相对 base 有修改时保留，否则传播删除。
      if (baseItem == null || !_jsonEqual(remoteItem, baseItem, toJson)) {
        merged.add(remoteItem);
      }
    }
  }

  return merged;
}

Map<String, ActivityLog> _mergeActivityLogs(
  Map<String, ActivityLog> local,
  Map<String, ActivityLog> remote,
) {
  final projectIds = <String>{...local.keys, ...remote.keys};
  return {
    for (final projectId in projectIds)
      projectId: (local[projectId] ?? const ActivityLog()).mergeWith(
        remote[projectId] ?? const ActivityLog(),
      ),
  };
}

/// 共享内容三路合并。
///
/// 标签、保存视图和模板按稳定 id 合并；并发编辑采用 updatedAt 较新一侧。
/// 活动历史是追加型数据，始终按事件 id 并集并由 ActivityLog 负责限长。
SharedContent mergeSharedContent({
  required SharedContent local,
  required SharedContent remote,
  SharedContent? base,
}) {
  // 旧端缺少 shared_content.json 时不得把另一侧内容误判为已删除。
  if (local.isUninitialized && !remote.isUninitialized) return remote;
  if (remote.isUninitialized && !local.isUninitialized) return local;
  if (local.isUninitialized && remote.isUninitialized) {
    return SharedContent.empty;
  }

  final baseValue = base ?? SharedContent.empty;
  final labels = _mergeEntitiesById<SharedLabel>(
    local: local.labels,
    remote: remote.labels,
    base: baseValue.labels,
    idOf: (item) => item.id,
    updatedAtOf: (item) => item.updatedAt,
    toJson: (item) => item.toJson(),
  );
  final savedViews = _mergeEntitiesById<SavedView>(
    local: local.savedViews,
    remote: remote.savedViews,
    base: baseValue.savedViews,
    idOf: (item) => item.id,
    updatedAtOf: (item) => item.updatedAt,
    toJson: (item) => item.toJson(),
  );
  final cardTemplates = _mergeEntitiesById<CardTemplate>(
    local: local.cardTemplates,
    remote: remote.cardTemplates,
    base: baseValue.cardTemplates,
    idOf: (item) => item.id,
    updatedAtOf: (item) => item.updatedAt,
    toJson: (item) => item.toJson(),
  );

  return SharedContent(
    labels: labels,
    savedViews: savedViews,
    cardTemplates: cardTemplates,
    activityByProject: _mergeActivityLogs(
      local.activityByProject,
      remote.activityByProject,
    ),
    updatedAt: local.updatedAt >= remote.updatedAt
        ? local.updatedAt
        : remote.updatedAt,
    revision:
        local.revision >= remote.revision ? local.revision : remote.revision,
  );
}
