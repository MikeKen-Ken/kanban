import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../../common/date_utils.dart';
import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../kanban/kanban_labels.dart';
import '../views/views.dart';

/// 向 [McpServer] 注册看板工具；所有写入经 [BoardController]。
void registerKanbanMcpTools(McpServer server, BoardController controller) {
  server.registerTool(
    'list_projects',
    description: '列出全部看板项目及当前激活项目',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations: const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final projects = [
        for (final project in controller.projects)
          {
            'id': project.id,
            'title': project.title,
            'active': project.id == controller.activeProjectId,
          },
      ];
      return _jsonResult({
        'activeProjectId': controller.activeProjectId,
        'projects': projects,
      });
    },
  );

  server.registerTool(
    'list_columns',
    description: '列出指定项目（默认当前项目）的列',
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(description: '项目 id，省略则用当前项目'),
      },
    ),
    annotations: const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final projectId =
          (args['projectId'] as String?)?.trim().isNotEmpty == true
              ? (args['projectId'] as String).trim()
              : controller.activeProjectId;
      if (projectId == null) {
        return _errorResult('没有可用项目');
      }
      final board = await controller.loadBoardSnapshot(projectId);
      if (board == null) {
        return _errorResult('项目不存在或未加载：$projectId');
      }
      return _jsonResult({
        'projectId': projectId,
        'columns': [
          for (final column in board.columns)
            {
              'id': column.id,
              'title': column.title,
              'cardCount': column.cards.length,
            },
        ],
      });
    },
  );

  server.registerTool(
    'search_cards',
    description: '跨项目搜索卡片（关键词、完成状态、项目）',
    inputSchema: JsonSchema.object(
      properties: {
        'keyword': JsonSchema.string(description: '标题/备注/标签关键词'),
        'projectId': JsonSchema.string(description: '限定项目 id'),
        'completed': JsonSchema.string(
          description: 'any | incomplete | completed，默认 incomplete',
        ),
        'limit': JsonSchema.number(description: '最多返回条数，默认 30'),
      },
    ),
    annotations: const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final keyword = (args['keyword'] as String?)?.trim() ?? '';
      final projectId = (args['projectId'] as String?)?.trim();
      final completedRaw =
          ((args['completed'] as String?) ?? 'incomplete').trim().toLowerCase();
      final limit = ((args['limit'] as num?)?.toInt() ?? 30).clamp(1, 100);

      final completion = switch (completedRaw) {
        'completed' || 'done' || 'true' => CompletionFilter.completed,
        'any' || 'all' => CompletionFilter.any,
        _ => CompletionFilter.incomplete,
      };

      final refs = await controller.loadAllCardReferences();
      final filtered = const CardQueryService().query(
        refs,
        FilterSpec(
          keyword: keyword,
          projectIds: projectId == null || projectId.isEmpty
              ? const []
              : [projectId],
          completion: completion,
        ),
      );
      final sliced = filtered.take(limit).map((card) => card.toJson()).toList();
      return _jsonResult({
        'count': sliced.length,
        'totalMatched': filtered.length,
        'cards': sliced,
      });
    },
  );

  server.registerTool(
    'get_card',
    description: '按 cardId 获取单张卡片详情',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'projectId': JsonSchema.string(description: '可选，缩小查找范围'),
      },
      required: ['cardId'],
    ),
    annotations: const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final cardId = (args['cardId'] as String?)?.trim() ?? '';
      if (cardId.isEmpty) return _errorResult('cardId 不能为空');
      final projectId = (args['projectId'] as String?)?.trim();
      final refs = await controller.loadAllCardReferences();
      final match = refs.cast<CardReference?>().firstWhere(
            (card) =>
                card!.cardId == cardId &&
                (projectId == null ||
                    projectId.isEmpty ||
                    card.projectId == projectId),
            orElse: () => null,
          );
      if (match == null) return _errorResult('未找到卡片：$cardId');
      return _jsonResult(match.toJson());
    },
  );

  server.registerTool(
    'today_cards',
    description: '列出今日视图：已逾期、今天到期、本周稍后的未完成卡片',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations: const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
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
      return _jsonResult({
        'overdue': overdue.map((card) => card.toJson()).toList(),
        'today': today.map((card) => card.toJson()).toList(),
        'thisWeek': thisWeek.map((card) => card.toJson()).toList(),
      });
    },
  );

  server.registerTool(
    'create_card',
    description: '在指定列创建卡片；可先切换到目标项目',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(description: '标题'),
        'columnId': JsonSchema.string(description: '列 id'),
        'projectId': JsonSchema.string(description: '项目 id，默认当前项目'),
        'description': JsonSchema.string(description: '备注'),
        'priority': JsonSchema.string(
          description: 'none | low | medium | high',
        ),
      },
      required: ['title', 'columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final title = (args['title'] as String?)?.trim() ?? '';
      final columnId = (args['columnId'] as String?)?.trim() ?? '';
      if (title.isEmpty) return _errorResult('title 不能为空');
      if (columnId.isEmpty) return _errorResult('columnId 不能为空');

      final projectId = (args['projectId'] as String?)?.trim();
      if (projectId != null &&
          projectId.isNotEmpty &&
          projectId != controller.activeProjectId) {
        await controller.switchProject(projectId);
      }

      final priority = _parsePriority(args['priority'] as String?);
      final description = (args['description'] as String?)?.trim();
      final cardId = await controller.addCard(
        columnId,
        title,
        description: description?.isEmpty == true ? null : description,
        priority: priority,
      );
      if (cardId == null) {
        return _errorResult('创建失败：请确认项目与列 id 有效');
      }
      return _jsonResult({
        'cardId': cardId,
        'projectId': controller.activeProjectId,
        'columnId': columnId,
        'title': title,
      });
    },
  );

  server.registerTool(
    'update_card',
    description: '更新卡片标题、备注、优先级或完成状态（需提供所在列）',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(),
        'columnId': JsonSchema.string(),
        'projectId': JsonSchema.string(description: '若卡片不在当前项目则先切换'),
        'title': JsonSchema.string(),
        'description': JsonSchema.string(),
        'priority': JsonSchema.string(),
        'completed': JsonSchema.boolean(),
      },
      required: ['cardId', 'columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = (args['cardId'] as String?)?.trim() ?? '';
      final columnId = (args['columnId'] as String?)?.trim() ?? '';
      if (cardId.isEmpty || columnId.isEmpty) {
        return _errorResult('cardId 与 columnId 均不能为空');
      }
      final projectId = (args['projectId'] as String?)?.trim();
      if (projectId != null &&
          projectId.isNotEmpty &&
          projectId != controller.activeProjectId) {
        await controller.switchProject(projectId);
      }

      await controller.updateCardFull(
        columnId,
        cardId,
        title: (args['title'] as String?)?.trim(),
        description: (args['description'] as String?)?.trim(),
        clearDescription: args.containsKey('description') &&
            ((args['description'] as String?)?.trim().isEmpty ?? true),
        priority: args['priority'] == null
            ? null
            : _parsePriority(args['priority'] as String?),
        completed: args['completed'] as bool?,
      );
      return _jsonResult({
        'ok': true,
        'cardId': cardId,
        'columnId': columnId,
      });
    },
  );

  server.registerTool(
    'move_card',
    description: '将卡片移动到另一列（可改显示位置）',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(),
        'fromColumnId': JsonSchema.string(),
        'toColumnId': JsonSchema.string(),
        'projectId': JsonSchema.string(),
        'toIndex': JsonSchema.number(description: '目标列显示下标，默认末尾'),
      },
      required: ['cardId', 'fromColumnId', 'toColumnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = (args['cardId'] as String?)?.trim() ?? '';
      final fromColumnId = (args['fromColumnId'] as String?)?.trim() ?? '';
      final toColumnId = (args['toColumnId'] as String?)?.trim() ?? '';
      if (cardId.isEmpty || fromColumnId.isEmpty || toColumnId.isEmpty) {
        return _errorResult('cardId / fromColumnId / toColumnId 不能为空');
      }
      final projectId = (args['projectId'] as String?)?.trim();
      if (projectId != null &&
          projectId.isNotEmpty &&
          projectId != controller.activeProjectId) {
        await controller.switchProject(projectId);
      }

      final board = controller.board;
      if (board == null) return _errorResult('看板未就绪');
      final toColumn = board.columns.cast<KanbanColumn?>().firstWhere(
            (column) => column!.id == toColumnId,
            orElse: () => null,
          );
      if (toColumn == null) return _errorResult('目标列不存在：$toColumnId');

      final toIndex = (args['toIndex'] as num?)?.toInt() ?? toColumn.cards.length;
      await controller.moveCard(
        cardId: cardId,
        fromColumnId: fromColumnId,
        toColumnId: toColumnId,
        toDisplayIndex: toIndex.clamp(0, toColumn.cards.length),
      );
      return _jsonResult({
        'ok': true,
        'cardId': cardId,
        'toColumnId': toColumnId,
      });
    },
  );

  server.registerTool(
    'complete_card',
    description: '将卡片标记为完成（会按项目设置移入已完成列）',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(),
        'columnId': JsonSchema.string(),
        'projectId': JsonSchema.string(),
      },
      required: ['cardId', 'columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = (args['cardId'] as String?)?.trim() ?? '';
      final columnId = (args['columnId'] as String?)?.trim() ?? '';
      if (cardId.isEmpty || columnId.isEmpty) {
        return _errorResult('cardId 与 columnId 均不能为空');
      }
      final projectId = (args['projectId'] as String?)?.trim();
      if (projectId != null &&
          projectId.isNotEmpty &&
          projectId != controller.activeProjectId) {
        await controller.switchProject(projectId);
      }

      final board = controller.board;
      if (board == null) return _errorResult('看板未就绪');
      KanbanCard? target;
      for (final column in board.columns) {
        if (column.id != columnId) continue;
        for (final card in column.cards) {
          if (card.id == cardId) {
            target = card;
            break;
          }
        }
      }
      if (target == null) return _errorResult('卡片不存在');
      if (!target.completed) {
        await controller.toggleCardCompleted(columnId, cardId);
      }
      return _jsonResult({'ok': true, 'cardId': cardId, 'completed': true});
    },
  );
}

CallToolResult _jsonResult(Object data) {
  return CallToolResult(
    content: [
      TextContent(text: const JsonEncoder.withIndent('  ').convert(data)),
    ],
  );
}

CallToolResult _errorResult(String message) {
  return CallToolResult(
    isError: true,
    content: [TextContent(text: message)],
  );
}

CardPriority _parsePriority(String? raw) {
  final value = (raw ?? 'none').trim().toLowerCase();
  return CardPriority.values.firstWhere(
    (item) => item.name == value,
    orElse: () => CardPriority.none,
  );
}
