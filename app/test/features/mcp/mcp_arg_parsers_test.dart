import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/mcp_arg_parsers.dart';
import 'package:kanban/features/views/filter_spec.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  group('parseMcpEpoch', () {
    test('解析整数毫秒', () {
      final result = parseMcpEpoch(1700000000000, fieldName: 'dueDate');
      expect(result.error, isNull);
      expect(result.value, 1700000000000);
    });

    test('解析数字字符串', () {
      final result = parseMcpEpoch('1700000000000', fieldName: 'dueDate');
      expect(result.value, 1700000000000);
    });

    test('解析 ISO8601', () {
      final result = parseMcpEpoch(
        '2026-08-04T12:00:00.000Z',
        fieldName: 'dueDate',
      );
      expect(result.error, isNull);
      expect(result.value, DateTime.parse('2026-08-04T12:00:00.000Z').millisecondsSinceEpoch);
    });

    test('非法字符串报错', () {
      final result = parseMcpEpoch('not-a-date', fieldName: 'dueDate');
      expect(result.hasError, isTrue);
      expect(result.error, contains('dueDate'));
    });

    test('空值返回空', () {
      expect(parseMcpEpoch(null, fieldName: 'dueDate').value, isNull);
      expect(parseMcpEpoch('', fieldName: 'dueDate').value, isNull);
    });
  });

  group('parseMcpPriority / recurrence', () {
    test('解析优先级', () {
      expect(parseMcpPriority('high').name, 'high');
      expect(parseMcpPriority('UNKNOWN').name, 'none');
    });

    test('解析重复', () {
      expect(parseMcpRecurrence('weekly'), CardRecurrence.weekly);
      expect(parseMcpRecurrence('nope'), CardRecurrence.none);
    });
  });

  group('parseMcpChecklist', () {
    test('字符串数组', () {
      final items = parseMcpChecklist(['写测试', '  ', '提交']);
      expect(items, isNotNull);
      expect(items!.length, 2);
      expect(items.map((item) => item.text), ['写测试', '提交']);
      expect(items.every((item) => item.id.isNotEmpty), isTrue);
    });

    test('对象数组保留 completed 与 id', () {
      final items = parseMcpChecklist([
        {'id': 'a1', 'text': '一步', 'completed': true},
        {'text': '二步'},
      ]);
      expect(items!.length, 2);
      expect(items[0].id, 'a1');
      expect(items[0].completed, isTrue);
      expect(items[1].text, '二步');
      expect(items[1].completed, isFalse);
      expect(items[1].id, isNotEmpty);
    });
  });

  group('parseMcpFilterSpec', () {
    test('默认 incomplete（search 兼容）', () {
      final filter = parseMcpFilterSpec(
        {'keyword': 'foo'},
        defaultCompletion: CompletionFilter.incomplete,
      );
      expect(filter.keyword, 'foo');
      expect(filter.completion, CompletionFilter.incomplete);
    });

    test('组合字段', () {
      final filter = parseMcpFilterSpec({
        'projectId': 'p1',
        'columnIds': ['c1', 'c2'],
        'labelIds': ['l1'],
        'labelMatchMode': 'all',
        'priorities': ['high', 'medium'],
        'completed': 'any',
        'dueDate': 'overdue',
        'sortField': 'priority',
        'sortDirection': 'desc',
      });
      expect(filter.projectIds, ['p1']);
      expect(filter.columnIds, ['c1', 'c2']);
      expect(filter.labelIds, ['l1']);
      expect(filter.labelMatchMode, LabelMatchMode.all);
      expect(filter.priorities, ['high', 'medium']);
      expect(filter.completion, CompletionFilter.any);
      expect(filter.dueDate, DueDateFilter.overdue);
      expect(filter.sortField, CardSortField.priority);
      expect(filter.sortDirection, SortDirection.descending);
    });

    test('嵌套 filter 与顶层覆盖', () {
      final filter = parseMcpFilterSpec({
        'filter': {
          'keyword': 'inner',
          'completed': 'completed',
        },
        'keyword': 'outer',
      });
      expect(filter.keyword, 'outer');
      expect(filter.completion, CompletionFilter.completed);
    });
  });

  group('parseMcpIdList / parseMcpLinks', () {
    test('id 列表忽略空白', () {
      expect(parseMcpIdList(null), isNull);
      expect(parseMcpIdList(['a', ' ', 'b']), ['a', 'b']);
      expect(parseMcpIdList([]), isEmpty);
    });

    test('外链支持字符串与对象', () {
      expect(parseMcpLinks(null), isNull);
      final links = parseMcpLinks([
        'https://a.example',
        {'id': 'l1', 'url': 'https://b.example', 'title': 'B'},
        {'url': '  '},
      ]);
      expect(links, isNotNull);
      expect(links!.length, 2);
      expect(links[0].url, 'https://a.example');
      expect(links[0].id, isNotEmpty);
      expect(links[1].id, 'l1');
      expect(links[1].title, 'B');
      expect(parseMcpLinks([]), isEmpty);
    });
  });

  group('mcpCardSummary', () {
    test('截断备注并汇总清单', () {
      final card = KanbanCard(
        id: 'c1',
        title: '标题',
        description: 'a' * 150,
        order: 0,
        createdAt: 1,
        checklist: [
          ChecklistItem(id: '1', text: 'a', completed: true),
          ChecklistItem(id: '2', text: 'b'),
        ],
        blockedByIds: const ['dep'],
        relatedIds: const ['rel'],
        links: [
          CardLink(
            id: 'l1',
            url: 'https://example.com',
            title: '文档',
            order: 0,
            createdAt: 1,
          ),
        ],
      );
      final summary = mcpCardSummary(card, descriptionMax: 10);
      expect(summary['description'], 'aaaaaaaaaa…');
      expect(summary['checklist'], {'done': 1, 'total': 2});
      expect(summary['blockedByIds'], ['dep']);
      expect(summary['relatedIds'], ['rel']);
      expect(summary['links'], [
        {
          'id': 'l1',
          'url': 'https://example.com',
          'title': '文档',
          'order': 0,
          'createdAt': 1,
        },
      ]);
    });
  });

  group('mcpTrimmedString / mcpLimit', () {
    test('裁剪与 limit 边界', () {
      expect(mcpTrimmedString(null), isNull);
      expect(mcpTrimmedString('  '), isNull);
      expect(mcpTrimmedString(' p1 '), 'p1');
      expect(mcpLimit(null), 30);
      expect(mcpLimit(0), 1);
      expect(mcpLimit(200), 100);
    });
  });
}
