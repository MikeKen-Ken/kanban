import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../views/card_reference.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

/// 注册卡片读写、移动与完成相关 MCP 工具。
void registerKanbanMcpCardTools(McpServer server, BoardController controller) {
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
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      if (cardId.isEmpty) return mcpErrorResult('cardId 不能为空');
      final projectId = mcpTrimmedString(args['projectId']);
      final refs = await controller.loadAllCardReferences();
      CardReference? match;
      for (final card in refs) {
        if (card.cardId != cardId) continue;
        if (projectId != null && card.projectId != projectId) continue;
        match = card;
        break;
      }
      if (match == null) return mcpErrorResult('未找到卡片：$cardId');
      return mcpJsonResult(match.toJson());
    },
  );

  server.registerTool(
    'create_card',
    description: '在指定列创建卡片；支持到期日、提醒、重复、标签与清单',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(description: '标题'),
        'columnId': JsonSchema.string(description: '列 id'),
        'projectId': JsonSchema.string(description: '项目 id，默认当前项目'),
        'description': JsonSchema.string(description: '备注'),
        'priority': JsonSchema.string(
          description: 'none | low | medium | high',
        ),
        'dueDate': JsonSchema.string(description: 'ISO8601 或 epoch 毫秒'),
        'reminderAt': JsonSchema.string(description: 'ISO8601 或 epoch 毫秒'),
        'recurrence': JsonSchema.string(
          description: 'none | daily | weekly | monthly',
        ),
        'labels': JsonSchema.array(
          items: JsonSchema.string(description: '标签 key'),
        ),
        'checklist': JsonSchema.array(
          items: JsonSchema.object(properties: {
            'text': JsonSchema.string(),
            'completed': JsonSchema.boolean(),
          }),
          description: '字符串数组或 {text,completed} 对象数组',
        ),
        'colorValue': JsonSchema.number(description: '卡片背景色 ARGB'),
      },
      required: ['title', 'columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final title = mcpTrimmedString(args['title']) ?? '';
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      if (title.isEmpty) return mcpErrorResult('title 不能为空');
      if (columnId.isEmpty) return mcpErrorResult('columnId 不能为空');

      final switchError =
          await ensureMcpProject(controller, args['projectId'] as String?);
      if (switchError != null) return switchError;

      final due = parseMcpEpoch(args['dueDate'], fieldName: 'dueDate');
      if (due.hasError) return mcpErrorResult(due.error!);
      final reminder =
          parseMcpEpoch(args['reminderAt'], fieldName: 'reminderAt');
      if (reminder.hasError) return mcpErrorResult(reminder.error!);

      final labels = (args['labels'] as List?)
              ?.whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList() ??
          const <String>[];
      final checklist = parseMcpChecklist(args['checklist']);
      final description = mcpTrimmedString(args['description']);
      final recurrence = args['recurrence'] == null
          ? CardRecurrence.none
          : parseMcpRecurrence(args['recurrence'] as String?);
      final colorValue = (args['colorValue'] as num?)?.toInt();

      final cardId = await controller.addCard(
        columnId,
        title,
        description: description,
        dueDate: due.value,
        reminderAt: reminder.value,
        recurrence: recurrence,
        priority: parseMcpPriority(args['priority'] as String?),
        labels: labels,
      );
      if (cardId == null) {
        return mcpErrorResult('创建失败：请确认项目与列 id 有效');
      }

      if (checklist != null || colorValue != null) {
        await controller.updateCardFull(
          columnId,
          cardId,
          checklist: checklist,
          colorValue: colorValue,
        );
      }

      return mcpJsonResult({
        'cardId': cardId,
        'projectId': controller.activeProjectId,
        'columnId': columnId,
        'title': title,
      });
    },
  );

  server.registerTool(
    'update_card',
    description: '更新卡片字段（需提供所在列）；支持到期日、提醒、重复、标签、清单与颜色',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(),
        'columnId': JsonSchema.string(),
        'projectId': JsonSchema.string(description: '若卡片不在当前项目则先切换'),
        'title': JsonSchema.string(),
        'description': JsonSchema.string(),
        'priority': JsonSchema.string(),
        'completed': JsonSchema.boolean(),
        'dueDate': JsonSchema.string(description: 'ISO8601 或 epoch 毫秒'),
        'clearDueDate': JsonSchema.boolean(),
        'reminderAt': JsonSchema.string(description: 'ISO8601 或 epoch 毫秒'),
        'clearReminder': JsonSchema.boolean(),
        'recurrence': JsonSchema.string(),
        'labels': JsonSchema.array(items: JsonSchema.string()),
        'checklist': JsonSchema.array(
          items: JsonSchema.object(properties: {
            'text': JsonSchema.string(),
            'completed': JsonSchema.boolean(),
          }),
        ),
        'blockedByIds': JsonSchema.array(
          items: JsonSchema.string(description: '阻塞本卡的卡片 id'),
        ),
        'relatedIds': JsonSchema.array(
          items: JsonSchema.string(description: '相关卡片 id'),
        ),
        'colorValue': JsonSchema.number(),
        'clearColor': JsonSchema.boolean(),
      },
      required: ['cardId', 'columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      if (cardId.isEmpty || columnId.isEmpty) {
        return mcpErrorResult('cardId 与 columnId 均不能为空');
      }
      final switchError =
          await ensureMcpProject(controller, args['projectId'] as String?);
      if (switchError != null) return switchError;

      final due = parseMcpEpoch(args['dueDate'], fieldName: 'dueDate');
      if (due.hasError) return mcpErrorResult(due.error!);
      final reminder =
          parseMcpEpoch(args['reminderAt'], fieldName: 'reminderAt');
      if (reminder.hasError) return mcpErrorResult(reminder.error!);

      final labels = args.containsKey('labels')
          ? (args['labels'] as List?)
                  ?.whereType<String>()
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList() ??
              const <String>[]
          : null;
      final checklist = args.containsKey('checklist')
          ? (parseMcpChecklist(args['checklist']) ?? const <ChecklistItem>[])
          : null;
      final blockedByIds = args.containsKey('blockedByIds')
          ? (args['blockedByIds'] as List?)
                  ?.whereType<String>()
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList() ??
              const <String>[]
          : null;
      final relatedIds = args.containsKey('relatedIds')
          ? (args['relatedIds'] as List?)
                  ?.whereType<String>()
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList() ??
              const <String>[]
          : null;

      await controller.updateCardFull(
        columnId,
        cardId,
        title: mcpTrimmedString(args['title']),
        description: (args['description'] as String?)?.trim(),
        clearDescription: args.containsKey('description') &&
            ((args['description'] as String?)?.trim().isEmpty ?? true),
        priority: args['priority'] == null
            ? null
            : parseMcpPriority(args['priority'] as String?),
        completed: args['completed'] as bool?,
        dueDate: due.value,
        clearDueDate: args['clearDueDate'] == true,
        reminderAt: reminder.value,
        clearReminder: args['clearReminder'] == true,
        recurrence: args['recurrence'] == null
            ? null
            : parseMcpRecurrence(args['recurrence'] as String?),
        labels: labels,
        checklist: checklist,
        blockedByIds: blockedByIds,
        relatedIds: relatedIds,
        colorValue: (args['colorValue'] as num?)?.toInt(),
        clearColor: args['clearColor'] == true,
      );
      return mcpJsonResult({
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
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      final fromColumnId = mcpTrimmedString(args['fromColumnId']) ?? '';
      final toColumnId = mcpTrimmedString(args['toColumnId']) ?? '';
      if (cardId.isEmpty || fromColumnId.isEmpty || toColumnId.isEmpty) {
        return mcpErrorResult('cardId / fromColumnId / toColumnId 不能为空');
      }
      final switchError =
          await ensureMcpProject(controller, args['projectId'] as String?);
      if (switchError != null) return switchError;

      final board = controller.board;
      if (board == null) return mcpErrorResult('看板未就绪');
      final toColumn = board.columns.cast<KanbanColumn?>().firstWhere(
            (column) => column!.id == toColumnId,
            orElse: () => null,
          );
      if (toColumn == null) return mcpErrorResult('目标列不存在：$toColumnId');

      final toIndex =
          (args['toIndex'] as num?)?.toInt() ?? toColumn.cards.length;
      await controller.moveCard(
        cardId: cardId,
        fromColumnId: fromColumnId,
        toColumnId: toColumnId,
        toDisplayIndex: toIndex.clamp(0, toColumn.cards.length),
      );
      return mcpJsonResult({
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
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      if (cardId.isEmpty || columnId.isEmpty) {
        return mcpErrorResult('cardId 与 columnId 均不能为空');
      }
      final switchError =
          await ensureMcpProject(controller, args['projectId'] as String?);
      if (switchError != null) return switchError;

      final board = controller.board;
      if (board == null) return mcpErrorResult('看板未就绪');
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
      if (target == null) return mcpErrorResult('卡片不存在');
      if (!target.completed) {
        await controller.toggleCardCompleted(columnId, cardId);
      }
      return mcpJsonResult({'ok': true, 'cardId': cardId, 'completed': true});
    },
  );

  server.registerTool(
    'delete_card',
    description: '删除卡片（进入回收站）',
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
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      if (cardId.isEmpty || columnId.isEmpty) {
        return mcpErrorResult('cardId 与 columnId 均不能为空');
      }
      final switchError =
          await ensureMcpProject(controller, args['projectId'] as String?);
      if (switchError != null) return switchError;
      await controller.deleteCard(columnId, cardId);
      return mcpJsonResult({'ok': true, 'cardId': cardId});
    },
  );
}
