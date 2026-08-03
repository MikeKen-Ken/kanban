import '../../models/kanban_models.dart';
import '../project/project_settings.dart';
import '../project/projects_manifest.dart';
import '../trash/trash_models.dart';
import '../kanban/column_card_preferences.dart';
import 'board_merge.dart';
import 'shared_content_merge.dart';
import 'workspace_snapshot.dart';

bool _prefsEq(
  Map<String, ColumnCardPreferences> a,
  Map<String, ColumnCardPreferences> b,
) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    final other = b[key];
    if (other == null) return false;
    if (a[key]!.sortMode != other.sortMode) return false;
    final ap = a[key]!.pinnedCardIds;
    final bp = other.pinnedCardIds;
    if (ap.length != bp.length) return false;
    for (var i = 0; i < ap.length; i++) {
      if (ap[i] != bp[i]) return false;
    }
  }
  return true;
}

bool _intMapEq(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// 从未真正写入过的默认设置（远端缺文件时常被填成这个）
bool _isUninitializedSettings(ProjectSettings s) =>
    s.updatedAt == 0 && s.revision == 0;

bool _settingsContentDiffers(ProjectSettings a, ProjectSettings b) =>
    a.doneColumnName != b.doneColumnName ||
    a.themeId != b.themeId ||
    !_prefsEq(a.columnPreferences, b.columnPreferences) ||
    !_intMapEq(a.columnWipLimits, b.columnWipLimits);

/// Settings：字段级合并；同字段冲突挂 conflictSide
ProjectSettings mergeSettings({
  required ProjectSettings local,
  required ProjectSettings remote,
  ProjectSettings? base,
}) {
  if (local.conflictSide != null || remote.conflictSide != null) {
    final winner = local.updatedAt >= remote.updatedAt ? local : remote;
    final other = winner.conflictSide;
    if (other == null) return winner;
    // note: 空默认桩或与主侧已无实质差异时，清掉陈旧冲突标记
    if (_isUninitializedSettings(other) ||
        !_settingsContentDiffers(winner, other)) {
      return winner.copyWith(clearConflictSide: true);
    }
    return winner;
  }

  if (base == null) {
    // note: 缺文件被填成默认桩时，直接采用已初始化一侧，避免幽灵冲突
    if (_isUninitializedSettings(local) && !_isUninitializedSettings(remote)) {
      return remote;
    }
    if (_isUninitializedSettings(remote) && !_isUninitializedSettings(local)) {
      return local;
    }
    if (_isUninitializedSettings(local) && _isUninitializedSettings(remote)) {
      return local;
    }

    final contentDiffers = _settingsContentDiffers(local, remote);
    final localWins = local.revision > remote.revision ||
        (local.revision == remote.revision &&
            local.updatedAt >= remote.updatedAt);
    final primary = localWins ? local : remote;
    final other = localWins ? remote : local;
    if (contentDiffers) {
      return primary.copyWith(
        conflictSide: other.copyWith(clearConflictSide: true),
      );
    }
    return primary;
  }

  // note: 三路合并时，未初始化一侧视为「未改动」，不参与冲突判定
  final effectiveLocal =
      _isUninitializedSettings(local) && !_isUninitializedSettings(base)
          ? base
          : local;
  final effectiveRemote =
      _isUninitializedSettings(remote) && !_isUninitializedSettings(base)
          ? base
          : remote;

  final doneLocalChanged = effectiveLocal.doneColumnName != base.doneColumnName;
  final doneRemoteChanged =
      effectiveRemote.doneColumnName != base.doneColumnName;
  final themeLocalChanged = effectiveLocal.themeId != base.themeId;
  final themeRemoteChanged = effectiveRemote.themeId != base.themeId;
  final prefsLocalChanged =
      !_prefsEq(effectiveLocal.columnPreferences, base.columnPreferences);
  final prefsRemoteChanged =
      !_prefsEq(effectiveRemote.columnPreferences, base.columnPreferences);
  final wipLocalChanged =
      !_intMapEq(effectiveLocal.columnWipLimits, base.columnWipLimits);
  final wipRemoteChanged =
      !_intMapEq(effectiveRemote.columnWipLimits, base.columnWipLimits);

  final doneConflict = doneLocalChanged &&
      doneRemoteChanged &&
      effectiveLocal.doneColumnName != effectiveRemote.doneColumnName;
  final themeConflict = themeLocalChanged &&
      themeRemoteChanged &&
      effectiveLocal.themeId != effectiveRemote.themeId;
  final prefsConflict = prefsLocalChanged &&
      prefsRemoteChanged &&
      !_prefsEq(
        effectiveLocal.columnPreferences,
        effectiveRemote.columnPreferences,
      );
  final wipConflict = wipLocalChanged &&
      wipRemoteChanged &&
      !_intMapEq(
        effectiveLocal.columnWipLimits,
        effectiveRemote.columnWipLimits,
      );

  if (doneConflict || themeConflict || prefsConflict || wipConflict) {
    final localWins = effectiveLocal.updatedAt >= effectiveRemote.updatedAt;
    final primary = localWins ? effectiveLocal : effectiveRemote;
    final other = localWins ? effectiveRemote : effectiveLocal;
    return primary.copyWith(
      conflictSide: other.copyWith(clearConflictSide: true),
      updatedAt: effectiveLocal.updatedAt >= effectiveRemote.updatedAt
          ? effectiveLocal.updatedAt
          : effectiveRemote.updatedAt,
      revision: effectiveLocal.revision >= effectiveRemote.revision
          ? effectiveLocal.revision
          : effectiveRemote.revision,
    );
  }

  return ProjectSettings(
    doneColumnName: doneLocalChanged
        ? effectiveLocal.doneColumnName
        : doneRemoteChanged
            ? effectiveRemote.doneColumnName
            : base.doneColumnName,
    themeId: themeLocalChanged
        ? effectiveLocal.themeId
        : themeRemoteChanged
            ? effectiveRemote.themeId
            : base.themeId,
    columnPreferences: prefsLocalChanged
        ? effectiveLocal.columnPreferences
        : prefsRemoteChanged
            ? effectiveRemote.columnPreferences
            : base.columnPreferences,
    columnWipLimits: wipLocalChanged
        ? effectiveLocal.columnWipLimits
        : wipRemoteChanged
            ? effectiveRemote.columnWipLimits
            : base.columnWipLimits,
    updatedAt: effectiveLocal.updatedAt >= effectiveRemote.updatedAt
        ? effectiveLocal.updatedAt
        : effectiveRemote.updatedAt,
    revision: effectiveLocal.revision >= effectiveRemote.revision
        ? effectiveLocal.revision
        : effectiveRemote.revision,
  );
}

bool _projectEntryChanged(ProjectEntry current, ProjectEntry base) {
  return current.title != base.title ||
      current.revision != base.revision ||
      current.updatedAt != base.updatedAt;
}

/// Manifest：有 SyncBase 时传播删除；无 base 时并集；同 id 标题冲突挂 conflictTitle
ProjectsManifest mergeManifests({
  required ProjectsManifest local,
  required ProjectsManifest remote,
  ProjectsManifest? base,
  Set<String> localContentChangedIds = const {},
  Set<String> remoteContentChangedIds = const {},
}) {
  final localById = {for (final p in local.projects) p.id: p};
  final remoteById = {for (final p in remote.projects) p.id: p};
  final baseById = {
    for (final p in base?.projects ?? const <ProjectEntry>[]) p.id: p,
  };

  final allIds = <String>{
    ...localById.keys,
    ...remoteById.keys,
  };

  final merged = <ProjectEntry>[];
  for (final id in allIds) {
    final l = localById[id];
    final r = remoteById[id];
    final b = baseById[id];

    if (l != null && r == null) {
      // 远端缺：无 base / 本地新建 → 保留；有 base 且未改 → 采纳删除；本地改过 → 删改冲突
      if (base == null || b == null) {
        merged.add(l);
        continue;
      }
      final localChanged =
          _projectEntryChanged(l, b) || localContentChangedIds.contains(id);
      if (localChanged) {
        merged.add(l.copyWith(conflictDeleted: true));
      }
      continue;
    }
    if (l == null && r != null) {
      // 本地缺：无 base / 远端新建 → 保留；有 base 且远端未改 → 采纳本地删除；远端改过 → 删改冲突
      if (base == null || b == null) {
        merged.add(r);
        continue;
      }
      final remoteChanged =
          _projectEntryChanged(r, b) || remoteContentChangedIds.contains(id);
      if (remoteChanged) {
        merged.add(r.copyWith(conflictDeleted: true));
      }
      continue;
    }
    if (l == null || r == null) continue;

    String title;
    String? conflictTitle;
    if (b != null) {
      final localChanged = l.title != b.title;
      final remoteChanged = r.title != b.title;
      if (localChanged && remoteChanged && l.title != r.title) {
        final localWins = l.updatedAt >= r.updatedAt;
        title = localWins ? l.title : r.title;
        conflictTitle = localWins ? r.title : l.title;
      } else if (localChanged) {
        title = l.title;
        conflictTitle = l.conflictTitle;
      } else if (remoteChanged) {
        title = r.title;
        conflictTitle = r.conflictTitle;
      } else {
        title = l.title;
        conflictTitle = l.conflictTitle ?? r.conflictTitle;
      }
    } else if (l.title != r.title) {
      final localWins = l.updatedAt >= r.updatedAt;
      title = localWins ? l.title : r.title;
      conflictTitle = localWins ? r.title : l.title;
    } else {
      title = l.title;
      conflictTitle = l.conflictTitle ?? r.conflictTitle;
    }

    final conflictDeleted = l.conflictDeleted || r.conflictDeleted;
    merged.add(
      ProjectEntry(
        id: id,
        title: title,
        updatedAt: l.updatedAt >= r.updatedAt ? l.updatedAt : r.updatedAt,
        revision: l.revision >= r.revision ? l.revision : r.revision,
        conflictTitle: conflictTitle,
        conflictDeleted: conflictDeleted,
      ),
    );
  }

  // note: 合并结果不能清空全部项目；若误删导致空清单，回退为并集保底
  if (merged.isEmpty && allIds.isNotEmpty) {
    for (final id in allIds) {
      final entry = localById[id] ?? remoteById[id];
      if (entry != null) merged.add(entry);
    }
  }

  return ProjectsManifest(
    projects: merged,
    updatedAt: local.updatedAt >= remote.updatedAt
        ? local.updatedAt
        : remote.updatedAt,
    revision:
        local.revision >= remote.revision ? local.revision : remote.revision,
  );
}

bool _boardMetaChanged(KanbanBoard? current, KanbanBoard? baseBoard) {
  if (current == null && baseBoard == null) return false;
  if (current == null || baseBoard == null) return true;
  return current.revision != baseBoard.revision ||
      current.updatedAt != baseBoard.updatedAt ||
      current.title != baseBoard.title;
}

bool _settingsMetaChanged(
    ProjectSettings? current, ProjectSettings? baseSettings) {
  final cur = current ?? const ProjectSettings();
  final baseVal = baseSettings ?? const ProjectSettings();
  if (_isUninitializedSettings(cur) && _isUninitializedSettings(baseVal)) {
    return false;
  }
  return cur.revision != baseVal.revision ||
      cur.updatedAt != baseVal.updatedAt ||
      _settingsContentDiffers(cur, baseVal);
}

Set<String> _contentChangedProjectIds({
  required ProjectWorkspaceSnapshot side,
  required ProjectWorkspaceSnapshot? base,
}) {
  if (base == null) return {};
  final ids = <String>{
    ...side.boards.keys,
    ...side.settings.keys,
    ...base.boards.keys,
    ...base.settings.keys,
  };
  final changed = <String>{};
  for (final id in ids) {
    if (_boardMetaChanged(side.boards[id], base.boards[id]) ||
        _settingsMetaChanged(side.settings[id], base.settings[id])) {
      changed.add(id);
    }
  }
  return changed;
}

bool _appTrashHasProject(TrashBin trash, String projectId) {
  return trash.items.any(
    (item) => item.type == TrashItemType.project && item.projectId == projectId,
  );
}

TrashBin _ensureDeletedProjectInAppTrash({
  required TrashBin appTrash,
  required String projectId,
  required ProjectEntry? entry,
  required KanbanBoard? board,
  required ProjectSettings? settings,
  required TrashBin? projectTrash,
}) {
  if (_appTrashHasProject(appTrash, projectId)) return appTrash;
  if (entry == null || board == null) return appTrash;
  return appTrash.bump().copyWith(
    items: [
      TrashItem.forProject(
        trashId: 'sync-del-$projectId',
        deletedAt: DateTime.now().millisecondsSinceEpoch,
        entry: entry.copyWith(clearConflict: true),
        board: board,
        settings: settings ?? const ProjectSettings(),
        projectTrash: projectTrash ?? TrashBin.empty,
      ),
      ...appTrash.items,
    ],
  );
}

/// 工作区三路合并入口
ProjectWorkspaceSnapshot mergeWorkspaces({
  required ProjectWorkspaceSnapshot local,
  required ProjectWorkspaceSnapshot remote,
  ProjectWorkspaceSnapshot? base,
}) {
  final localChangedIds = _contentChangedProjectIds(side: local, base: base);
  final remoteChangedIds = _contentChangedProjectIds(side: remote, base: base);

  final mergedManifest = mergeManifests(
    local: local.manifest,
    remote: remote.manifest,
    base: base?.manifest,
    localContentChangedIds: localChangedIds,
    remoteContentChangedIds: remoteChangedIds,
  );

  final mergedIds = mergedManifest.projects.map((p) => p.id).toSet();
  final priorIds = <String>{
    ...local.manifest.projects.map((p) => p.id),
    ...remote.manifest.projects.map((p) => p.id),
    ...?base?.manifest.projects.map((p) => p.id),
  };
  final deletedIds = priorIds.difference(mergedIds);

  final mergedBoards = <String, KanbanBoard>{};
  final mergedSettings = <String, ProjectSettings>{};
  final mergedProjectTrash = <String, TrashBin>{};

  for (final id in mergedIds) {
    final localBoard = local.boards[id];
    final remoteBoard = remote.boards[id];
    final baseBoard = base?.boards[id];

    if (localBoard != null && remoteBoard != null) {
      mergedBoards[id] = mergeBoards(
        local: localBoard,
        remote: remoteBoard,
        base: baseBoard,
      );
    } else {
      final only = localBoard ?? remoteBoard;
      if (only != null) mergedBoards[id] = only;
    }

    mergedSettings[id] = mergeSettings(
      local: local.settings[id] ?? const ProjectSettings(),
      remote: remote.settings[id] ?? const ProjectSettings(),
      base: base?.settings[id],
    );

    final localTrash = local.projectTrash[id] ?? TrashBin.empty;
    final remoteTrash = remote.projectTrash[id] ?? TrashBin.empty;
    mergedProjectTrash[id] = localTrash.mergeWith(remoteTrash);
  }

  var appTrash = local.appTrash.mergeWith(remote.appTrash);
  final localById = {
    for (final p in local.manifest.projects) p.id: p,
  };
  final remoteById = {
    for (final p in remote.manifest.projects) p.id: p,
  };
  final baseById = {
    for (final p in base?.manifest.projects ?? const <ProjectEntry>[]) p.id: p,
  };

  for (final id in deletedIds) {
    appTrash = _ensureDeletedProjectInAppTrash(
      appTrash: appTrash,
      projectId: id,
      entry: localById[id] ?? remoteById[id] ?? baseById[id],
      board: local.boards[id] ?? remote.boards[id] ?? base?.boards[id],
      settings: local.settings[id] ?? remote.settings[id] ?? base?.settings[id],
      projectTrash: local.projectTrash[id] ??
          remote.projectTrash[id] ??
          base?.projectTrash[id],
    );
  }

  return ProjectWorkspaceSnapshot(
    manifest: mergedManifest,
    boards: mergedBoards,
    settings: mergedSettings,
    projectTrash: mergedProjectTrash,
    appTrash: appTrash,
    sharedContent: mergeSharedContent(
      local: local.sharedContent,
      remote: remote.sharedContent,
      base: base?.sharedContent,
    ),
  );
}
