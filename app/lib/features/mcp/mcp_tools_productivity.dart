import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../quick_capture/quick_capture.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

/// 注册快速捕获、模板、回收站、撤销与置顶相关工具。
void registerKanbanMcpProductivityTools(
  McpServer server,
  BoardController controller,
) {
  server.registerTool(
    'pin_card',
    description: '切换卡片在列内的置顶状态',
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
      return runMcpForProject(controller, args['projectId'] as String?,
          (projectId) async {
        await controller.toggleCardPin(columnId, cardId);
        return mcpJsonResult({
          'ok': true,
          'cardId': cardId,
          'columnId': columnId,
          'projectId': projectId,
          'pinned': controller.isCardPinned(columnId, cardId),
        });
      });
    },
  );

  server.registerTool(
    'quick_capture',
    description:
        '快速录入一行文本（支持 #标签 !优先级 @列名 今天/明天 等指令）并创建卡片',
    inputSchema: JsonSchema.object(
      properties: {
        'text': JsonSchema.string(),
        'projectId': JsonSchema.string(),
      },
      required: ['text'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final text = mcpTrimmedString(args['text']) ?? '';
      if (text.isEmpty) return mcpErrorResult('text 不能为空');
      return runMcpForProject(controller, args['projectId'] as String?,
          (projectId) async {
        final draft = parseQuickCapture(text);
        final cardId = await controller.quickCapture(draft);
        if (cardId == null) {
          return mcpErrorResult('录入失败：请确认标题非空且看板已就绪');
        }
        return mcpJsonResult({
          'cardId': cardId,
          'projectId': projectId,
          'draft': {
            'title': draft.title,
            'labels': draft.labels,
            if (draft.priority != null) 'priority': draft.priority!.name,
            if (draft.columnName != null) 'columnName': draft.columnName,
            if (draft.dueDate != null)
              'dueDate': draft.dueDate!.millisecondsSinceEpoch,
          },
        });
      });
    },
  );

  server.registerTool(
    'list_templates',
    description: '列出卡片模板',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      return mcpJsonResult({
        'templates': [
          for (final template in controller.cardTemplates) template.toJson(),
        ],
      });
    },
  );

  server.registerTool(
    'save_card_as_template',
    description: '将现有卡片保存为模板（不含图片附件）',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(),
        'columnId': JsonSchema.string(),
        'name': JsonSchema.string(description: '模板名称'),
        'projectId': JsonSchema.string(),
      },
      required: ['cardId', 'columnId', 'name'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      final name = mcpTrimmedString(args['name']) ?? '';
      if (cardId.isEmpty || columnId.isEmpty || name.isEmpty) {
        return mcpErrorResult('cardId / columnId / name 均不能为空');
      }
      return runMcpForProject(controller, args['projectId'] as String?,
          (projectId) async {
        final board = controller.board;
        if (board == null) return mcpErrorResult('看板未就绪');
        KanbanCard? card;
        for (final column in board.columns) {
          if (column.id != columnId) continue;
          for (final item in column.cards) {
            if (item.id == cardId) {
              card = item;
              break;
            }
          }
        }
        if (card == null) return mcpErrorResult('未找到卡片');
        final templateId = await controller.saveCardAsTemplate(
          card: card,
          name: name,
        );
        return mcpJsonResult({
          'ok': true,
          'templateId': templateId,
          'name': name,
          'projectId': projectId,
        });
      });
    },
  );

  server.registerTool(
    'create_card_from_template',
    description: '从模板在指定列创建卡片',
    inputSchema: JsonSchema.object(
      properties: {
        'templateId': JsonSchema.string(),
        'columnId': JsonSchema.string(),
        'projectId': JsonSchema.string(),
      },
      required: ['templateId', 'columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final templateId = mcpTrimmedString(args['templateId']) ?? '';
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      if (templateId.isEmpty || columnId.isEmpty) {
        return mcpErrorResult('templateId 与 columnId 均不能为空');
      }
      return runMcpForProject(controller, args['projectId'] as String?,
          (projectId) async {
        final cardId = await controller.createCardFromTemplate(
          templateId: templateId,
          columnId: columnId,
        );
        if (cardId == null) {
          return mcpErrorResult('创建失败：模板或列无效');
        }
        return mcpJsonResult({
          'ok': true,
          'cardId': cardId,
          'columnId': columnId,
          'templateId': templateId,
          'projectId': projectId,
        });
      });
    },
  );

  server.registerTool(
    'delete_template',
    description: '删除卡片模板',
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
      await controller.deleteCardTemplate(id);
      return mcpJsonResult({'ok': true, 'id': id});
    },
  );

  server.registerTool(
    'list_trash',
    description: '列出回收站条目',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final items = controller.allTrashItems;
      return mcpJsonResult({
        'count': items.length,
        'items': [
          for (final item in items)
            {
              'id': item.id,
              'type': item.type.name,
              'displayName': item.displayName,
              'deletedAt': item.deletedAt,
              if (item.projectId != null) 'projectId': item.projectId,
              if (item.projectTitle != null) 'projectTitle': item.projectTitle,
              if (item.columnId != null) 'columnId': item.columnId,
              if (item.columnTitle != null) 'columnTitle': item.columnTitle,
            },
        ],
      });
    },
  );

  server.registerTool(
    'restore_trash_item',
    description: '从回收站恢复条目',
    inputSchema: JsonSchema.object(
      properties: {
        'id': JsonSchema.string(),
      },
      required: ['id'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final id = mcpTrimmedString(args['id']) ?? '';
      if (id.isEmpty) return mcpErrorResult('id 不能为空');
      final error = await controller.restoreTrashItem(id);
      if (error != null) return mcpErrorResult(error);
      return mcpJsonResult({'ok': true, 'id': id});
    },
  );

  server.registerTool(
    'permanently_delete_trash_item',
    description: '永久删除回收站条目',
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
      await controller.permanentlyDeleteTrashItem(id);
      return mcpJsonResult({'ok': true, 'id': id});
    },
  );

  server.registerTool(
    'empty_trash',
    description: '清空回收站',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final count = controller.trashItemCount;
      await controller.emptyTrash();
      return mcpJsonResult({'ok': true, 'deletedCount': count});
    },
  );

  server.registerTool(
    'undo_last_action',
    description: '撤销上一次可撤销操作',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      if (!controller.canUndo) {
        return mcpErrorResult('没有可撤销的操作');
      }
      final label = controller.undoLabel;
      final ok = await controller.undoLastAction();
      if (!ok) return mcpErrorResult('撤销失败');
      return mcpJsonResult({'ok': true, 'undone': label});
    },
  );
}
