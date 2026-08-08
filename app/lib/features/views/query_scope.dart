/// 搜索范围层级：全部项目 / 单个项目 / 项目内单列。
enum QueryScopeKind {
  allProjects,
  project,
  column,
}

/// 跨项目搜索的范围选择结果。
class QueryScope {
  const QueryScope.allProjects()
      : kind = QueryScopeKind.allProjects,
        projectId = null,
        columnId = null;

  const QueryScope.project(this.projectId)
      : kind = QueryScopeKind.project,
        columnId = null;

  const QueryScope.column({
    required this.projectId,
    required this.columnId,
  }) : kind = QueryScopeKind.column;

  final QueryScopeKind kind;
  final String? projectId;
  final String? columnId;

  /// 从筛选条件推断当前范围；多项目/多列时回退为全部项目。
  factory QueryScope.fromFilter({
    required List<String> projectIds,
    required List<String> columnIds,
  }) {
    if (columnIds.length == 1) {
      final columnId = columnIds.single;
      final projectId = projectIds.length == 1 ? projectIds.single : null;
      return QueryScope.column(projectId: projectId, columnId: columnId);
    }
    if (projectIds.length == 1 && columnIds.isEmpty) {
      return QueryScope.project(projectIds.single);
    }
    return const QueryScope.allProjects();
  }

  List<String> get projectIds =>
      projectId == null || projectId!.isEmpty ? const [] : [projectId!];

  List<String> get columnIds =>
      columnId == null || columnId!.isEmpty ? const [] : [columnId!];
}
