import 'package:flutter/material.dart';

import 'card_reference.dart';
import 'query_scope.dart';

/// 从卡片引用构建可选的项目与列目录。
class QueryScopeCatalog {
  QueryScopeCatalog(Iterable<CardReference> cards) {
    final projectNames = <String, String>{};
    final columnsByProject = <String, Map<String, String>>{};
    for (final card in cards) {
      projectNames.putIfAbsent(
        card.projectId,
        () => card.projectName.isEmpty ? '未命名项目' : card.projectName,
      );
      final columns = columnsByProject.putIfAbsent(
        card.projectId,
        () => <String, String>{},
      );
      columns.putIfAbsent(
        card.columnId,
        () => card.columnName.isEmpty ? '未命名列' : card.columnName,
      );
    }
    projects = Map.fromEntries(
      projectNames.entries.toList()
        ..sort((left, right) => left.value.compareTo(right.value)),
    );
    this.columnsByProject = {
      for (final entry in columnsByProject.entries)
        entry.key: Map.fromEntries(
          entry.value.entries.toList()
            ..sort((left, right) => left.value.compareTo(right.value)),
        ),
    };
  }

  late final Map<String, String> projects;
  late final Map<String, Map<String, String>> columnsByProject;

  String labelFor(QueryScope scope) {
    switch (scope.kind) {
      case QueryScopeKind.allProjects:
        return '全部项目';
      case QueryScopeKind.project:
        final name = projects[scope.projectId];
        return name == null ? '指定项目' : '项目：$name';
      case QueryScopeKind.column:
        final resolvedProjectId = scope.projectId ??
            columnsByProject.entries
                .where((entry) => entry.value.containsKey(scope.columnId))
                .map((entry) => entry.key)
                .firstOrNull;
        final projectName = projects[resolvedProjectId] ?? '指定项目';
        final columns =
            columnsByProject[resolvedProjectId] ?? const <String, String>{};
        final columnName = columns[scope.columnId] ?? '指定列';
        return '$projectName · $columnName';
    }
  }
}

/// 弹出底部面板，选择全部项目 / 某一项目 / 某一列。
Future<QueryScope?> showQueryScopePicker({
  required BuildContext context,
  required QueryScopeCatalog catalog,
  required QueryScope current,
}) {
  return showModalBottomSheet<QueryScope>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _QueryScopePickerSheet(
      catalog: catalog,
      current: current,
    ),
  );
}

class _QueryScopePickerSheet extends StatelessWidget {
  const _QueryScopePickerSheet({
    required this.catalog,
    required this.current,
  });

  final QueryScopeCatalog catalog;
  final QueryScope current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '选择搜索范围',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              key: const ValueKey('query-scope-all'),
              leading: const Icon(Icons.apps_outlined),
              title: const Text('全部项目'),
              trailing: current.kind == QueryScopeKind.allProjects
                  ? const Icon(Icons.check)
                  : null,
              onTap: () =>
                  Navigator.pop(context, const QueryScope.allProjects()),
            ),
            if (catalog.projects.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无项目可选'),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final project in catalog.projects.entries) ...[
                      ListTile(
                        key: ValueKey('query-scope-project-${project.key}'),
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(project.value),
                        subtitle: const Text('整个项目'),
                        trailing: current.kind == QueryScopeKind.project &&
                                current.projectId == project.key
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(
                          context,
                          QueryScope.project(project.key),
                        ),
                      ),
                      for (final column
                          in (catalog.columnsByProject[project.key] ?? const {})
                              .entries)
                        ListTile(
                          key: ValueKey(
                            'query-scope-column-${project.key}-${column.key}',
                          ),
                          contentPadding:
                              const EdgeInsets.only(left: 56, right: 16),
                          leading: const Icon(Icons.view_week_outlined),
                          title: Text(column.value),
                          subtitle: Text('${project.value} · 单列'),
                          trailing: current.kind == QueryScopeKind.column &&
                                  current.projectId == project.key &&
                                  current.columnId == column.key
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(
                            context,
                            QueryScope.column(
                              projectId: project.key,
                              columnId: column.key,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
