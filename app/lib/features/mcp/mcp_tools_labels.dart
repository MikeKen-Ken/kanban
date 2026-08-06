import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../kanban/kanban_labels.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

/// 注册标签相关 MCP 工具。
void registerKanbanMcpLabelTools(McpServer server, BoardController controller) {
  server.registerTool(
    'list_labels',
    description: '列出预置与自定义标签（可按项目主题）',
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(description: '用于选择预置主题，默认当前项目'),
      },
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final projectId = mcpTrimmedString(args['projectId']) ??
          controller.uiActiveProjectId;
      final themeId =
          projectId == null ? '' : controller.themeIdForProject(projectId);
      final labels = allKanbanLabels(
        controller.appSettings.customLabels,
        themeId: themeId,
      );
      final customKeys = {
        for (final label in controller.appSettings.customLabels) label.key,
      };
      return mcpJsonResult({
        'projectId': projectId,
        'themeId': themeId,
        'labels': [
          for (final label in labels)
            {
              ...label.toJson(),
              'custom': customKeys.contains(label.key),
            },
        ],
      });
    },
  );

  server.registerTool(
    'add_label',
    description: '新增自定义标签',
    inputSchema: JsonSchema.object(
      properties: {
        'name': JsonSchema.string(),
        'colorValue': JsonSchema.number(description: 'ARGB int'),
      },
      required: ['name', 'colorValue'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final name = mcpTrimmedString(args['name']) ?? '';
      final colorValue = (args['colorValue'] as num?)?.toInt();
      if (name.isEmpty) return mcpErrorResult('name 不能为空');
      if (colorValue == null) return mcpErrorResult('colorValue 不能为空');
      final key = await controller.addCustomLabel(name, colorValue);
      return mcpJsonResult({
        'ok': true,
        'key': key,
        'name': name,
        'colorValue': colorValue,
      });
    },
  );

  server.registerTool(
    'update_label',
    description: '更新自定义标签名称或颜色',
    inputSchema: JsonSchema.object(
      properties: {
        'key': JsonSchema.string(description: '标签 key'),
        'name': JsonSchema.string(),
        'colorValue': JsonSchema.number(description: 'ARGB int'),
      },
      required: ['key', 'name', 'colorValue'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final key = mcpTrimmedString(args['key']) ?? '';
      final name = mcpTrimmedString(args['name']) ?? '';
      final colorValue = (args['colorValue'] as num?)?.toInt();
      if (key.isEmpty) return mcpErrorResult('key 不能为空');
      if (name.isEmpty) return mcpErrorResult('name 不能为空');
      if (colorValue == null) return mcpErrorResult('colorValue 不能为空');
      final ok = await controller.updateCustomLabel(
        key,
        name: name,
        colorValue: colorValue,
      );
      if (!ok) return mcpErrorResult('更新失败：标签不存在或名称无效');
      return mcpJsonResult({
        'ok': true,
        'key': key,
        'name': name,
        'colorValue': colorValue,
      });
    },
  );

  server.registerTool(
    'remove_label',
    description: '删除自定义标签（进入回收站）',
    inputSchema: JsonSchema.object(
      properties: {
        'key': JsonSchema.string(),
      },
      required: ['key'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final key = mcpTrimmedString(args['key']) ?? '';
      if (key.isEmpty) return mcpErrorResult('key 不能为空');
      await controller.removeCustomLabel(key);
      return mcpJsonResult({'ok': true, 'key': key});
    },
  );
}
