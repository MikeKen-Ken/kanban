import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/views/views.dart';

void main() {
  group('FilterSpec JSON', () {
    test('新格式往返保留筛选和排序', () {
      const original = FilterSpec(
        keyword: '发布',
        projectIds: ['p1', 'p2'],
        columnIds: ['doing'],
        labelIds: ['urgent', 'backend'],
        labelMatchMode: LabelMatchMode.all,
        priorities: ['high'],
        completion: CompletionFilter.incomplete,
        dueDate: DueDateFilter.thisWeek,
        sortField: CardSortField.priority,
        sortDirection: SortDirection.descending,
      );

      final restored = FilterSpec.fromJson(original.toJson());

      expect(restored.keyword, '发布');
      expect(restored.projectIds, ['p1', 'p2']);
      expect(restored.columnIds, ['doing']);
      expect(restored.labelIds, ['urgent', 'backend']);
      expect(restored.labelMatchMode, LabelMatchMode.all);
      expect(restored.priorities, ['high']);
      expect(restored.completion, CompletionFilter.incomplete);
      expect(restored.dueDate, DueDateFilter.thisWeek);
      expect(restored.sortField, CardSortField.priority);
      expect(restored.sortDirection, SortDirection.descending);
    });

    test('旧版单值和字段别名可安全读取', () {
      final restored = FilterSpec.fromJson({
        'query': '旧查询',
        'projectId': 'p1',
        'columnId': 'todo',
        'labels': 'urgent',
        'priority': 'high',
        'completed': false,
        'dueToday': true,
        'sortBy': 'updatedAt',
        'ascending': false,
      });

      expect(restored.keyword, '旧查询');
      expect(restored.projectIds, ['p1']);
      expect(restored.columnIds, ['todo']);
      expect(restored.labelIds, ['urgent']);
      expect(restored.priorities, ['high']);
      expect(restored.completion, CompletionFilter.incomplete);
      expect(restored.dueDate, DueDateFilter.today);
      expect(restored.sortField, CardSortField.updatedAt);
      expect(restored.sortDirection, SortDirection.descending);
    });

    test('缺失及未知字段回退到默认值', () {
      final restored = FilterSpec.fromJson({
        'completion': 'future-value',
        'dueDate': 'future-value',
        'sortField': 'future-value',
        'sortDirection': 'future-value',
        'projectIds': [1, 'p1', null],
      });

      expect(restored.projectIds, ['p1']);
      expect(restored.completion, CompletionFilter.any);
      expect(restored.dueDate, DueDateFilter.any);
      expect(restored.sortField, CardSortField.dueDate);
      expect(restored.sortDirection, SortDirection.ascending);
    });
  });

  group('SavedView JSON', () {
    test('保存视图往返保留元数据', () {
      const view = SavedView(
        id: 'view-1',
        name: '本周重点',
        filter: FilterSpec(priorities: ['high']),
        createdAt: 10,
        updatedAt: 20,
      );

      final restored = SavedView.fromJson(view.toJson());

      expect(restored.id, 'view-1');
      expect(restored.name, '本周重点');
      expect(restored.filter.priorities, ['high']);
      expect(restored.createdAt, 10);
      expect(restored.updatedAt, 20);
    });

    test('兼容筛选字段位于根节点的旧视图', () {
      final restored = SavedView.fromJson({
        'id': 'legacy',
        'name': '旧视图',
        'projectId': 'p1',
        'overdue': true,
      });

      expect(restored.filter.projectIds, ['p1']);
      expect(restored.filter.dueDate, DueDateFilter.overdue);
      expect(restored.createdAt, 0);
    });
  });

  test('CardReference JSON 不序列化原始对象并兼容旧字段', () {
    final source = Object();
    final reference = CardReference(
      projectId: 'p1',
      projectName: '工作',
      columnId: 'todo',
      columnName: '待办',
      cardId: 'c1',
      title: '任务',
      source: source,
      labelIds: const ['urgent'],
      blockedByIds: const ['b1'],
      relatedIds: const ['r1'],
      links: const [
        {'id': 'l1', 'url': 'https://example.com', 'title': '文档'},
      ],
    );

    final json = reference.toJson();
    final restored = CardReference.fromJson({
      ...json,
      'projectTitle': '被新字段覆盖',
      'columnTitle': '被新字段覆盖',
    });

    expect(json.containsKey('source'), isFalse);
    expect(restored.projectName, '工作');
    expect(restored.columnName, '待办');
    expect(restored.labelIds, ['urgent']);
    expect(restored.blockedByIds, ['b1']);
    expect(restored.relatedIds, ['r1']);
    expect(restored.links, [
      {'id': 'l1', 'url': 'https://example.com', 'title': '文档'},
    ]);
    expect(restored.source, isNull);
  });
}
