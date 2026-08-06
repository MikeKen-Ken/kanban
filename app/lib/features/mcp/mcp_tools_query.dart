import 'package:mcp_dart/mcp_dart.dart';

import '../../common/date_utils.dart';
import '../../controllers/board_controller.dart';
import '../views/views.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

/// 注册搜索、整板、今日、统计、活动与保存视图相关工具。
void registerKanbanMcpQueryTools(McpServer server, BoardController controller) {
  server.registerTool(
    'list_board',
    description: '列出指定项目整板快照（列 + 卡片摘要）',
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(description: '省略则用当前项目'),
      },
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final projectId =
          mcpTrimmedString(args['projectId']) ?? controller.activeProjectId;
      if (projectId == null) return mcpErrorResult('没有可用项目');
      final board = await controller.loadBoardSnapshot(projectId);
      if (board == null) {
        return mcpErrorResult('项目不存在或未加载：$projectId');
      }
      return mcpJsonResult({
        'projectId': projectId,
        'title': board.title,
        'columns': [
          for (final column in board.columns)
            {
              'id': column.id,
              'title': column.title,
              if (column.colorValue != null) 'colorValue': column.colorValue,
              'cards': [
                for (final card in column.cards) mcpCardSummary(card),
              ],
            },
        ],
      });
    },
  );

  server.registerTool(
    'search_cards',
    description: '跨项目组合筛选搜索卡片（关键词、标签、优先级、到期、列、排序）',
    inputSchema: JsonSchema.object(
      properties: {
        'keyword': JsonSchema.string(description: '标题/备注/标签关键词'),
        'projectId': JsonSchema.string(description: '限定单个项目 id'),
        'projectIds': JsonSchema.array(items: JsonSchema.string()),
        'columnIds': JsonSchema.array(items: JsonSchema.string()),
        'labelIds': JsonSchema.array(items: JsonSchema.string()),
        'labelMatchMode': JsonSchema.string(description: 'any | all'),
        'priorities': JsonSchema.array(items: JsonSchema.string()),
        'completed': JsonSchema.string(
          description: 'any | incomplete | completed，默认 incomplete',
        ),
        'dueDate': JsonSchema.string(
          description: 'any | today | overdue | thisWeek',
        ),
        'sortField': JsonSchema.string(
          description:
              'dueDate | priority | title | createdAt | updatedAt | project | column | manual',
        ),
        'sortDirection': JsonSchema.string(description: 'ascending | descending'),
        'limit': JsonSchema.number(description: '最多返回条数，默认 30'),
      },
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final filter = parseMcpFilterSpec(
        Map<String, dynamic>.from(args),
        defaultCompletion: CompletionFilter.incomplete,
      );
      final limit = mcpLimit(args['limit']);
      final refs = await controller.loadAllCardReferences();
      final filtered = const CardQueryService().query(refs, filter);
      final sliced = filtered.take(limit).map((card) => card.toJson()).toList();
      return mcpJsonResult({
        'count': sliced.length,
        'totalMatched': filtered.length,
        'filter': filter.toJson(),
        'cards': sliced,
      });
    },
  );

  server.registerTool(
    'today_cards',
    description: '列出今日视图：已逾期、今天到期、本周稍后的未完成卡片',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final now = DateTime.now();
      final refs = await controller.loadAllCardReferences();
      final incomplete = refs
          .where((card) => !card.completed && card.dueDate != null)
          .toList()
        ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
      final overdue =
          incomplete.where((card) => isOverdue(card.dueDate!, now)).toList();
      final today =
          incomplete.where((card) => isDueToday(card.dueDate!, now)).toList();
      final thisWeek = incomplete
          .where(
            (card) =>
                !isOverdue(card.dueDate!, now) &&
                !isDueToday(card.dueDate!, now) &&
                isDueThisWeek(card.dueDate!, now),
          )
          .toList();
      return mcpJsonResult({
        'overdue': overdue.map((card) => card.toJson()).toList(),
        'today': today.map((card) => card.toJson()).toList(),
        'thisWeek': thisWeek.map((card) => card.toJson()).toList(),
      });
    },
  );

  server.registerTool(
    'list_saved_views',
    description: '列出已保存的筛选视图',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      return mcpJsonResult({
        'views': [
          for (final view in controller.savedViews) view.toJson(),
        ],
      });
    },
  );

  server.registerTool(
    'save_view',
    description: '创建或更新保存视图；filter 可用嵌套对象或与 search_cards 相同的扁平字段',
    inputSchema: JsonSchema.object(
      properties: {
        'id': JsonSchema.string(description: '省略则新建'),
        'name': JsonSchema.string(),
        'keyword': JsonSchema.string(),
        'projectIds': JsonSchema.array(items: JsonSchema.string()),
        'columnIds': JsonSchema.array(items: JsonSchema.string()),
        'labelIds': JsonSchema.array(items: JsonSchema.string()),
        'labelMatchMode': JsonSchema.string(),
        'priorities': JsonSchema.array(items: JsonSchema.string()),
        'completed': JsonSchema.string(),
        'dueDate': JsonSchema.string(),
        'sortField': JsonSchema.string(),
        'sortDirection': JsonSchema.string(),
      },
      required: ['name'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final name = mcpTrimmedString(args['name']) ?? '';
      if (name.isEmpty) return mcpErrorResult('name 不能为空');
      final filter = parseMcpFilterSpec(Map<String, dynamic>.from(args));
      final id = mcpTrimmedString(args['id']);
      await controller.saveView(id: id, name: name, filter: filter);
      SavedView? saved;
      for (final view in controller.savedViews) {
        if (id != null && view.id == id) {
          saved = view;
          break;
        }
        if (id == null && view.name == name) saved = view;
      }
      saved ??=
          controller.savedViews.isEmpty ? null : controller.savedViews.last;
      return mcpJsonResult({
        'ok': true,
        if (saved != null) 'view': saved.toJson(),
      });
    },
  );

  server.registerTool(
    'delete_saved_view',
    description: '删除保存视图',
    inputSchema: JsonSchema.object(
      properties: {
        'id': JsonSchema.string(),
      },
      required: ['id'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final id = mcpTrimmedString(args['id']) ?? '';
      if (id.isEmpty) return mcpErrorResult('id 不能为空');
      await controller.deleteSavedView(id);
      return mcpJsonResult({'ok': true, 'id': id});
    },
  );

  server.registerTool(
    'query_saved_view',
    description: '按保存视图 id 执行筛选查询',
    inputSchema: JsonSchema.object(
      properties: {
        'id': JsonSchema.string(),
        'limit': JsonSchema.number(description: '最多返回条数，默认 30'),
      },
      required: ['id'],
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final id = mcpTrimmedString(args['id']) ?? '';
      if (id.isEmpty) return mcpErrorResult('id 不能为空');
      SavedView? view;
      for (final item in controller.savedViews) {
        if (item.id == id) {
          view = item;
          break;
        }
      }
      if (view == null) return mcpErrorResult('未找到视图：$id');
      final limit = mcpLimit(args['limit']);
      final refs = await controller.loadAllCardReferences();
      final filtered = const CardQueryService().query(refs, view.filter);
      final sliced = filtered.take(limit).map((card) => card.toJson()).toList();
      return mcpJsonResult({
        'view': view.toJson(),
        'count': sliced.length,
        'totalMatched': filtered.length,
        'cards': sliced,
      });
    },
  );

  server.registerTool(
    'get_statistics',
    description: '获取跨项目统计摘要',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final stats = await controller.loadStatistics();
      return mcpJsonResult({
        'total': stats.total,
        'completed': stats.completed,
        'active': stats.active,
        'overdue': stats.overdue,
        'completedLast7Days': stats.completedLast7Days,
        'averageCompletionHours': stats.averageCompletionHours,
        'byProject': stats.byProject,
      });
    },
  );

  server.registerTool(
    'list_activity',
    description:
        '列出项目活动历史（新到旧）；含 source=user|mcp|automation，便于区分 MCP 改动',
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(description: '省略则用当前项目'),
        'limit': JsonSchema.number(description: '最多返回条数，默认 50'),
      },
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final resolved =
          resolveMcpProjectId(controller, args['projectId'] as String?);
      if (resolved.error != null) return resolved.error!;
      final projectId = resolved.projectId!;
      final limit = mcpLimit(args['limit'], fallback: 50);
      final events = controller.activityForProject(projectId).take(limit).toList();
      return mcpJsonResult({
        'projectId': projectId,
        'count': events.length,
        'events': [for (final event in events) event.toJson()],
      });
    },
  );
}
