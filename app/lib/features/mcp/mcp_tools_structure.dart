import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

/// 注册项目与列结构相关 MCP 工具。
void registerKanbanMcpStructureTools(
  McpServer server,
  BoardController controller,
) {
  server.registerTool(
    'list_projects',
    description: '列出全部看板项目及当前激活项目',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final projects = [
        for (final project in controller.projects)
          {
            'id': project.id,
            'title': project.title,
            'active': project.id == controller.activeProjectId,
          },
      ];
      return mcpJsonResult({
        'activeProjectId': controller.activeProjectId,
        'projects': projects,
      });
    },
  );

  server.registerTool(
    'create_project',
    description: '创建新看板项目并切换为当前项目',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(description: '项目标题'),
      },
      required: ['title'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final title = mcpTrimmedString(args['title']) ?? '';
      if (title.isEmpty) return mcpErrorResult('title 不能为空');
      await controller.createProject(title);
      return mcpJsonResult({
        'ok': true,
        'projectId': controller.activeProjectId,
        'title': title,
      });
    },
  );

  server.registerTool(
    'rename_project',
    description: '重命名指定项目（默认当前项目）',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(),
        'projectId': JsonSchema.string(description: '省略则重命名当前项目'),
      },
      required: ['title'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final title = mcpTrimmedString(args['title']) ?? '';
      if (title.isEmpty) return mcpErrorResult('title 不能为空');
      final projectId =
          mcpTrimmedString(args['projectId']) ?? controller.activeProjectId;
      if (projectId == null) return mcpErrorResult('没有可用项目');
      await controller.renameProject(projectId, title);
      return mcpJsonResult({
        'ok': true,
        'projectId': projectId,
        'title': title,
      });
    },
  );

  server.registerTool(
    'switch_project',
    description: '切换当前激活项目',
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(),
      },
      required: ['projectId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final projectId = mcpTrimmedString(args['projectId']) ?? '';
      if (projectId.isEmpty) return mcpErrorResult('projectId 不能为空');
      final switchError = await ensureMcpProject(controller, projectId);
      if (switchError != null) return switchError;
      return mcpJsonResult({
        'ok': true,
        'projectId': controller.activeProjectId,
      });
    },
  );

  server.registerTool(
    'delete_project',
    description: '删除项目（进入回收站）',
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(),
      },
      required: ['projectId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final projectId = mcpTrimmedString(args['projectId']) ?? '';
      if (projectId.isEmpty) return mcpErrorResult('projectId 不能为空');
      final ok = await controller.deleteProject(projectId);
      if (!ok) return mcpErrorResult('删除失败：项目不存在或无法删除');
      return mcpJsonResult({'ok': true, 'projectId': projectId});
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
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final projectId = mcpTrimmedString(args['projectId']) ??
          controller.activeProjectId;
      if (projectId == null) return mcpErrorResult('没有可用项目');
      final board = await controller.loadBoardSnapshot(projectId);
      if (board == null) {
        return mcpErrorResult('项目不存在或未加载：$projectId');
      }
      return mcpJsonResult({
        'projectId': projectId,
        'columns': [
          for (final column in board.columns)
            {
              'id': column.id,
              'title': column.title,
              'cardCount': column.cards.length,
              if (column.colorValue != null) 'colorValue': column.colorValue,
            },
        ],
      });
    },
  );

  server.registerTool(
    'add_column',
    description: '在当前项目新增列',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(),
        'projectId': JsonSchema.string(),
      },
      required: ['title'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final title = mcpTrimmedString(args['title']) ?? '';
      if (title.isEmpty) return mcpErrorResult('title 不能为空');
      final switchError =
          await ensureMcpProject(controller, args['projectId'] as String?);
      if (switchError != null) return switchError;
      await controller.addColumn(title);
      final columnId = controller.board?.columns.isNotEmpty == true
          ? controller.board!.columns.last.id
          : null;
      return mcpJsonResult({
        'ok': true,
        'projectId': controller.activeProjectId,
        if (columnId != null) 'columnId': columnId,
        'title': title,
      });
    },
  );

  server.registerTool(
    'rename_column',
    description: '重命名列',
    inputSchema: JsonSchema.object(
      properties: {
        'columnId': JsonSchema.string(),
        'title': JsonSchema.string(),
        'projectId': JsonSchema.string(),
      },
      required: ['columnId', 'title'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      final title = mcpTrimmedString(args['title']) ?? '';
      if (columnId.isEmpty || title.isEmpty) {
        return mcpErrorResult('columnId 与 title 均不能为空');
      }
      final switchError =
          await ensureMcpProject(controller, args['projectId'] as String?);
      if (switchError != null) return switchError;
      await controller.renameColumn(columnId, title);
      return mcpJsonResult({
        'ok': true,
        'columnId': columnId,
        'title': title,
      });
    },
  );

  server.registerTool(
    'delete_column',
    description: '删除列（进入回收站）',
    inputSchema: JsonSchema.object(
      properties: {
        'columnId': JsonSchema.string(),
        'projectId': JsonSchema.string(),
      },
      required: ['columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      if (columnId.isEmpty) return mcpErrorResult('columnId 不能为空');
      final switchError =
          await ensureMcpProject(controller, args['projectId'] as String?);
      if (switchError != null) return switchError;
      await controller.deleteColumn(columnId);
      return mcpJsonResult({'ok': true, 'columnId': columnId});
    },
  );

  server.registerTool(
    'reorder_column',
    description: '调整列顺序',
    inputSchema: JsonSchema.object(
      properties: {
        'oldIndex': JsonSchema.number(description: '原下标（从 0 起）'),
        'newIndex': JsonSchema.number(description: '目标下标（从 0 起）'),
        'projectId': JsonSchema.string(),
      },
      required: ['oldIndex', 'newIndex'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final oldIndex = (args['oldIndex'] as num?)?.toInt();
      final newIndex = (args['newIndex'] as num?)?.toInt();
      if (oldIndex == null || newIndex == null) {
        return mcpErrorResult('oldIndex 与 newIndex 均不能为空');
      }
      final switchError =
          await ensureMcpProject(controller, args['projectId'] as String?);
      if (switchError != null) return switchError;
      await controller.reorderColumn(oldIndex, newIndex);
      return mcpJsonResult({
        'ok': true,
        'oldIndex': oldIndex,
        'newIndex': newIndex,
      });
    },
  );

  server.registerTool(
    'update_column_color',
    description: '设置列主题色（ARGB）；传 null/省略 colorValue 并设 clear=true 可清除',
    inputSchema: JsonSchema.object(
      properties: {
        'columnId': JsonSchema.string(),
        'colorValue': JsonSchema.number(description: 'ARGB int'),
        'clear': JsonSchema.boolean(description: '清除列颜色'),
        'projectId': JsonSchema.string(),
      },
      required: ['columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      if (columnId.isEmpty) return mcpErrorResult('columnId 不能为空');
      final switchError =
          await ensureMcpProject(controller, args['projectId'] as String?);
      if (switchError != null) return switchError;
      final clear = args['clear'] == true;
      final colorValue =
          clear ? null : (args['colorValue'] as num?)?.toInt();
      await controller.updateColumnColor(columnId, colorValue);
      return mcpJsonResult({
        'ok': true,
        'columnId': columnId,
        'colorValue': colorValue,
      });
    },
  );
}
