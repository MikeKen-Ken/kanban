import '../../models/kanban_models.dart';
import '../project/project_settings.dart';
import '../project/projects_manifest.dart';
import '../trash/trash_models.dart';
import '../kanban/column_card_preferences.dart';
import 'board_merge.dart';
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

/// Manifest：按项目 id 并集；同 id 标题冲突时挂 conflictTitle
ProjectsManifest mergeManifests({
  required ProjectsManifest local,
  required ProjectsManifest remote,
  ProjectsManifest? base,
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
      // 远端删：若有 base 且本地未改标题/条目，可接受删除；第一期并集保留本地新增/仍在侧
      if (base != null && b != null && !localById.containsKey(id)) {
        continue;
      }
      merged.add(l);
      continue;
    }
    if (l == null && r != null) {
      merged.add(r);
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

    merged.add(
      ProjectEntry(
        id: id,
        title: title,
        updatedAt: l.updatedAt >= r.updatedAt ? l.updatedAt : r.updatedAt,
        revision: l.revision >= r.revision ? l.revision : r.revision,
        conflictTitle: conflictTitle,
      ),
    );
  }

  return ProjectsManifest(
    projects: merged,
    updatedAt:
        local.updatedAt >= remote.updatedAt ? local.updatedAt : remote.updatedAt,
    revision:
        local.revision >= remote.revision ? local.revision : remote.revision,
  );
}

/// Settings：字段级合并；同字段冲突挂 conflictSide
ProjectSettings mergeSettings({
  required ProjectSettings local,
  required ProjectSettings remote,
  ProjectSettings? base,
}) {
  if (local.conflictSide != null || remote.conflictSide != null) {
    return local.updatedAt >= remote.updatedAt ? local : remote;
  }

  if (base == null) {
    final contentDiffers = local.doneColumnName != remote.doneColumnName ||
        local.themeId != remote.themeId ||
        !_prefsEq(local.columnPreferences, remote.columnPreferences);
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

  final doneLocalChanged = local.doneColumnName != base.doneColumnName;
  final doneRemoteChanged = remote.doneColumnName != base.doneColumnName;
  final themeLocalChanged = local.themeId != base.themeId;
  final themeRemoteChanged = remote.themeId != base.themeId;
  final prefsLocalChanged =
      !_prefsEq(local.columnPreferences, base.columnPreferences);
  final prefsRemoteChanged =
      !_prefsEq(remote.columnPreferences, base.columnPreferences);

  final doneConflict = doneLocalChanged &&
      doneRemoteChanged &&
      local.doneColumnName != remote.doneColumnName;
  final themeConflict = themeLocalChanged &&
      themeRemoteChanged &&
      local.themeId != remote.themeId;
  final prefsConflict = prefsLocalChanged &&
      prefsRemoteChanged &&
      !_prefsEq(local.columnPreferences, remote.columnPreferences);

  if (doneConflict || themeConflict || prefsConflict) {
    final localWins = local.updatedAt >= remote.updatedAt;
    final primary = localWins ? local : remote;
    final other = localWins ? remote : local;
    return primary.copyWith(
      conflictSide: other.copyWith(clearConflictSide: true),
      updatedAt: local.updatedAt >= remote.updatedAt
          ? local.updatedAt
          : remote.updatedAt,
      revision:
          local.revision >= remote.revision ? local.revision : remote.revision,
    );
  }

  return ProjectSettings(
    doneColumnName: doneLocalChanged
        ? local.doneColumnName
        : doneRemoteChanged
            ? remote.doneColumnName
            : base.doneColumnName,
    themeId: themeLocalChanged
        ? local.themeId
        : themeRemoteChanged
            ? remote.themeId
            : base.themeId,
    columnPreferences: prefsLocalChanged
        ? local.columnPreferences
        : prefsRemoteChanged
            ? remote.columnPreferences
            : base.columnPreferences,
    updatedAt:
        local.updatedAt >= remote.updatedAt ? local.updatedAt : remote.updatedAt,
    revision:
        local.revision >= remote.revision ? local.revision : remote.revision,
  );
}

/// 工作区三路合并入口
ProjectWorkspaceSnapshot mergeWorkspaces({
  required ProjectWorkspaceSnapshot local,
  required ProjectWorkspaceSnapshot remote,
  ProjectWorkspaceSnapshot? base,
}) {
  final mergedManifest = mergeManifests(
    local: local.manifest,
    remote: remote.manifest,
    base: base?.manifest,
  );

  final allIds = <String>{
    ...local.boards.keys,
    ...remote.boards.keys,
    ...mergedManifest.projects.map((p) => p.id),
  };

  final mergedBoards = <String, KanbanBoard>{};
  final mergedSettings = <String, ProjectSettings>{};
  final mergedProjectTrash = <String, TrashBin>{};

  for (final id in allIds) {
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

  return ProjectWorkspaceSnapshot(
    manifest: mergedManifest,
    boards: mergedBoards,
    settings: mergedSettings,
    projectTrash: mergedProjectTrash,
    appTrash: local.appTrash.mergeWith(remote.appTrash),
  );
}
