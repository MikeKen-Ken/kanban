import 'dart:convert';

import '../features/sync_conflict/workspace_snapshot.dart';
import '../features/trash/trash_models.dart';
import '../models/kanban_models.dart';

/// 远端 JSON 上传项种类
enum SyncUploadKind {
  projectsManifest,
  appTrash,
  sharedContent,
  boardMetadata,
  column,
  settings,
  trash,
}

/// 一次待上传的 JSON 逻辑文件
class SyncUploadItem {
  const SyncUploadItem({
    required this.kind,
    required this.label,
    required this.json,
    this.projectId,
    this.columnId,
  });

  final SyncUploadKind kind;
  final String label;
  final Object json;
  final String? projectId;
  final String? columnId;
}

/// 相对基线计算出的增量上传计划
class SyncUploadPlan {
  const SyncUploadPlan({
    required this.items,
    required this.keepProjectIds,
    required this.keepColumnIdsByProject,
    required this.projectsNeedingColumnCleanup,
    required this.needsProjectCleanup,
    required this.skippedFileCount,
  });

  final List<SyncUploadItem> items;
  final Set<String> keepProjectIds;
  final Map<String, Set<String>> keepColumnIdsByProject;

  /// 有列增删或列内容变化、需清理远端孤儿列的项目
  final Set<String> projectsNeedingColumnCleanup;

  /// 是否需要扫描并清理远端孤儿项目目录
  final bool needsProjectCleanup;

  final int skippedFileCount;

  bool get isEmpty =>
      items.isEmpty &&
      !needsProjectCleanup &&
      projectsNeedingColumnCleanup.isEmpty;
}

bool syncJsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  return jsonEncode(a) == jsonEncode(b);
}

/// 相对 [baseline] 计算需上传的 JSON；[baseline] 为 null 时全量上传。
SyncUploadPlan buildSyncUploadPlan({
  required ProjectWorkspaceSnapshot workspace,
  ProjectWorkspaceSnapshot? baseline,
}) {
  final items = <SyncUploadItem>[];
  var skipped = 0;

  void consider({
    required SyncUploadKind kind,
    required String label,
    required Object current,
    required Object? previous,
    String? projectId,
    String? columnId,
  }) {
    if (baseline != null && syncJsonEquals(current, previous)) {
      skipped++;
      return;
    }
    items.add(
      SyncUploadItem(
        kind: kind,
        label: label,
        json: current,
        projectId: projectId,
        columnId: columnId,
      ),
    );
  }

  consider(
    kind: SyncUploadKind.projectsManifest,
    label: '项目清单',
    current: workspace.manifest.toJson(),
    previous: baseline?.manifest.toJson(),
  );
  consider(
    kind: SyncUploadKind.appTrash,
    label: '应用回收站',
    current: workspace.appTrash.toJson(),
    previous: baseline?.appTrash.toJson(),
  );
  if (!workspace.sharedContent.isUninitialized) {
    consider(
      kind: SyncUploadKind.sharedContent,
      label: '共享内容',
      current: workspace.sharedContent.toJson(),
      previous: baseline?.sharedContent.isUninitialized == true
          ? null
          : baseline?.sharedContent.toJson(),
    );
  }

  final keepProjectIds = workspace.manifest.projects.map((p) => p.id).toSet();
  final keepColumnIdsByProject = <String, Set<String>>{};
  final projectsNeedingColumnCleanup = <String>{};

  for (final entry in workspace.manifest.projects) {
    final projectId = entry.id;
    final board = workspace.boards[projectId];
    final settings = workspace.settings[projectId];
    final trash = workspace.projectTrash[projectId] ?? TrashBin.empty;
    if (board == null || settings == null) continue;

    final baseBoard = baseline?.boards[projectId];
    final baseSettings = baseline?.settings[projectId];
    final baseTrash = baseline?.projectTrash[projectId];
    final columnIds = board.columns.map((c) => c.id).toSet();
    keepColumnIdsByProject[projectId] = columnIds;

    final baseColumnIds =
        baseBoard?.columns.map((c) => c.id).toSet() ?? const <String>{};
    final columnsRemoved = baseline != null &&
        baseColumnIds.any((id) => !columnIds.contains(id));

    final title = entry.title.trim().isEmpty ? projectId : entry.title;

    consider(
      kind: SyncUploadKind.boardMetadata,
      label: '$title / 看板',
      current: board.toMetadataJson(),
      previous: baseBoard?.toMetadataJson(),
      projectId: projectId,
    );
    consider(
      kind: SyncUploadKind.settings,
      label: '$title / 设置',
      current: settings.toJson(),
      previous: baseSettings?.toJson(),
      projectId: projectId,
    );
    consider(
      kind: SyncUploadKind.trash,
      label: '$title / 回收站',
      current: trash.toJson(),
      previous: baseTrash?.toJson(),
      projectId: projectId,
    );

    final baseColumnsById = <String, KanbanColumn>{
      for (final column in baseBoard?.columns ?? const <KanbanColumn>[])
        column.id: column,
    };

    var anyColumnChanged = false;
    for (final column in board.columns) {
      final previous = baseColumnsById[column.id]?.toJson();
      final before = items.length;
      consider(
        kind: SyncUploadKind.column,
        label: '$title / ${column.title}',
        current: column.toJson(),
        previous: previous,
        projectId: projectId,
        columnId: column.id,
      );
      if (items.length > before) {
        anyColumnChanged = true;
      }
    }

    if (columnsRemoved || anyColumnChanged || baseline == null) {
      projectsNeedingColumnCleanup.add(projectId);
    }
  }

  final baselineProjectIds =
      baseline?.manifest.projects.map((p) => p.id).toSet() ?? const <String>{};
  final needsProjectCleanup = baseline == null ||
      baselineProjectIds.any((id) => !keepProjectIds.contains(id));

  return SyncUploadPlan(
    items: items,
    keepProjectIds: keepProjectIds,
    keepColumnIdsByProject: keepColumnIdsByProject,
    projectsNeedingColumnCleanup: projectsNeedingColumnCleanup,
    needsProjectCleanup: needsProjectCleanup,
    skippedFileCount: skipped,
  );
}

/// 相对 SyncBase 待上传的 JSON 文件数（跨全部项目；含清单/共享/设置/列等）
int countPendingSyncUploads({
  required ProjectWorkspaceSnapshot workspace,
  ProjectWorkspaceSnapshot? baseline,
}) {
  return buildSyncUploadPlan(
    workspace: workspace,
    baseline: baseline,
  ).items.length;
}

/// 供测试与调试：汇总计划中涉及的项目 id
Set<String> syncUploadPlanTouchedProjectIds(SyncUploadPlan plan) {
  return {
    for (final item in plan.items)
      if (item.projectId != null) item.projectId!,
    ...plan.projectsNeedingColumnCleanup,
  };
}