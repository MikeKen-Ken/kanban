import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/views/query_scope.dart';

void main() {
  test('从筛选条件推断全部 / 项目 / 列范围', () {
    expect(
      QueryScope.fromFilter(projectIds: const [], columnIds: const []).kind,
      QueryScopeKind.allProjects,
    );

    final project = QueryScope.fromFilter(
      projectIds: const ['work'],
      columnIds: const [],
    );
    expect(project.kind, QueryScopeKind.project);
    expect(project.projectIds, ['work']);
    expect(project.columnIds, isEmpty);

    final column = QueryScope.fromFilter(
      projectIds: const ['work'],
      columnIds: const ['todo'],
    );
    expect(column.kind, QueryScopeKind.column);
    expect(column.projectIds, ['work']);
    expect(column.columnIds, ['todo']);

    final multi = QueryScope.fromFilter(
      projectIds: const ['work', 'home'],
      columnIds: const [],
    );
    expect(multi.kind, QueryScopeKind.allProjects);
  });
}
