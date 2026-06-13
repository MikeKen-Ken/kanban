import 'projects_manifest.dart';

/// 项目列表排序方式
enum ProjectSortMode {
  recentlyUsed('最近使用'),
  name('名称'),
  defaultOrder('默认');

  const ProjectSortMode(this.label);

  final String label;

  static ProjectSortMode fromName(String? name) {
    return ProjectSortMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => ProjectSortMode.defaultOrder,
    );
  }
}

/// 根据本地偏好对项目列表排序（置顶项始终在最前）
List<ProjectEntry> sortProjectEntries(
  List<ProjectEntry> projects, {
  required ProjectSortMode sortMode,
  required List<String> pinnedProjectIds,
  required Map<String, int> lastUsedAtByProjectId,
}) {
  if (projects.isEmpty) return const [];

  final byId = {for (final p in projects) p.id: p};
  final pinned = <ProjectEntry>[
    for (final id in pinnedProjectIds)
      if (byId.containsKey(id)) byId[id]!,
  ];
  final pinnedSet = pinned.map((p) => p.id).toSet();

  final unpinned = projects.where((p) => !pinnedSet.contains(p.id)).toList();
  switch (sortMode) {
    case ProjectSortMode.name:
      unpinned.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    case ProjectSortMode.recentlyUsed:
      unpinned.sort((a, b) {
        final aTime = lastUsedAtByProjectId[a.id] ?? a.updatedAt;
        final bTime = lastUsedAtByProjectId[b.id] ?? b.updatedAt;
        return bTime.compareTo(aTime);
      });
    case ProjectSortMode.defaultOrder:
      break;
  }

  return [...pinned, ...unpinned];
}
