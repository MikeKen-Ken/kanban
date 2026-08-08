import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../activity/activity_models.dart';
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
            'active': project.id == controller.uiActiveProjectId,
          },
      ];
      return mcpJsonResult({
        'activeProjectId': controller.uiActiveProjectId,
        'projects': projects,
      });
    },
  );

  server.registerTool(
    'create_project',
    description: '创建新看板项目但不切换界面当前项目',
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
      final projectId = await controller.createProjectData(title);
      return mcpJsonResult({
        'ok': true,
        'projectId': projectId,
        'title': title,
      });
    },
  );

  server.registerTool(
    'rename_project',
    description:
        '重命名指定项目。多项目时必须传 projectId，避免改到界面当前项目',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(),
        'projectId': JsonSchema.string(
          description: '多项目时必填；单项目可省略（重命名唯一项目）',
        ),
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
      final resolved = resolveMcpProjectId(
        controller,
        args['projectId'] as String?,
        requireExplicitWhenMultiple: true,
      );
      if (resolved.error != null) return resolved.error!;
      final projectId = resolved.projectId!;
      await controller.runWithActivitySource(
        ActivitySource.mcp,
        () => controller.renameProject(projectId, title),
      );
      return mcpJsonResult({
        'ok': true,
        'projectId': projectId,
        'title': title,
      });
    },
  );

  server.registerTool(
    'switch_project',
    description: '校验目标项目；不会切换界面，后续操作仍需显式传 projectId',
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(),
      },
      required: ['projectId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: true,
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
        'projectId': projectId,
        'uiActiveProjectId': controller.uiActiveProjectId,
        'message': '界面未切换；请在后续工具调用中继续显式传入 projectId',
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
      if (projectId == controller.uiActiveProjectId) {
        return mcpErrorResult('MCP 不能删除界面当前项目，请先由用户在界面切换项目');
      }
      final ok = await controller.deleteProjectInBackground(projectId);
      if (!ok) {
        return mcpErrorResult('删除失败：项目不存在、无法删除或已成为界面当前项目');
      }
      return mcpJsonResult({'ok': true, 'projectId': projectId});
    },
  );

  server.registerTool(
    'list_columns',
    description: '列出指定项目（默认界面当前项目）的列',
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(
          description: '项目 id；省略则用界面当前项目（非 runOnProject 临时作用域）',
        ),
      },
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final projectId = mcpTrimmedString(args['projectId']) ??
          controller.uiActiveProjectId;
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
    description:
        '在指定项目新增列；可用 beforeColumnId / insertIndex 插入到指定位置'
        '（例如在已完成列前插入「待返工」）。多项目时必须传 projectId',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(),
        'projectId': JsonSchema.string(
          description: '项目 id；多项目时必填',
        ),
        'beforeColumnId': JsonSchema.string(
          description: '插入到该列之前（优先于 insertIndex）',
        ),
        'insertIndex': JsonSchema.number(
          description: '插入下标（从 0 起）；省略则追加到末尾',
        ),
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
      return runMcpForProject(
        controller,
        args['projectId'] as String?,
        (projectId) async {
        final beforeColumnId = mcpTrimmedString(args['beforeColumnId']);
        final insertIndex = (args['insertIndex'] as num?)?.toInt();
        final error = await controller.addColumn(
          title,
          beforeColumnId: beforeColumnId,
          insertIndex: insertIndex,
        );
        if (error != null) return mcpErrorResult(error);
        final columns = controller.board?.columns ?? const <KanbanColumn>[];
        final column = columns.cast<KanbanColumn?>().firstWhere(
              (col) => col!.title == title,
              orElse: () => columns.isNotEmpty ? columns.last : null,
            );
        return mcpJsonResult({
          'ok': true,
          'projectId': projectId,
          if (column != null) 'columnId': column.id,
          'title': title,
          if (column != null)
            'index': columns.indexWhere((col) => col.id == column.id),
        });
      },
        requireExplicitWhenMultiple: true,
      );
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
      return runMcpForProject(controller, args['projectId'] as String?,
          (projectId) async {
        final error = await controller.renameColumn(columnId, title);
        if (error != null) return mcpErrorResult(error);
        return mcpJsonResult({
          'ok': true,
          'columnId': columnId,
          'title': title,
          'projectId': projectId,
        });
      }, requireExplicitWhenMultiple: true);
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
      return runMcpForProject(controller, args['projectId'] as String?,
          (projectId) async {
        await controller.deleteColumn(columnId);
        return mcpJsonResult({
          'ok': true,
          'columnId': columnId,
          'projectId': projectId,
        });
      }, requireExplicitWhenMultiple: true);
    },
  );

  server.registerTool(
    'reorder_column',
    description:
        '调整列顺序（例如把「待返工」移到待验证与已完成之间）。'
        'newIndex 语义与 Flutter ReorderableList 一致',
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
      return runMcpForProject(controller, args['projectId'] as String?,
          (projectId) async {
        await controller.reorderColumn(oldIndex, newIndex);
        return mcpJsonResult({
          'ok': true,
          'oldIndex': oldIndex,
          'newIndex': newIndex,
          'projectId': projectId,
        });
      }, requireExplicitWhenMultiple: true);
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
      return runMcpForProject(controller, args['projectId'] as String?,
          (projectId) async {
        final clear = args['clear'] == true;
        final colorValue =
            clear ? null : (args['colorValue'] as num?)?.toInt();
        await controller.updateColumnColor(columnId, colorValue);
        return mcpJsonResult({
          'ok': true,
          'columnId': columnId,
          'colorValue': colorValue,
          'projectId': projectId,
        });
      }, requireExplicitWhenMultiple: true);
    },
  );
}
