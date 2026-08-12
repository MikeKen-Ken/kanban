import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

void registerKanbanMcpRelationTools(
  McpServer server,
  BoardController controller,
) {
  _registerRelationTool(
    server,
    controller,
    name: 'link_cards',
    description: '在同一项目内原子建立两张卡的双向关联；重复调用保持幂等。',
    related: true,
  );
  _registerRelationTool(
    server,
    controller,
    name: 'unlink_cards',
    description: '在同一项目内原子解除两张卡的双向关联；重复调用保持幂等。',
    related: false,
  );
}

void _registerRelationTool(
  McpServer server,
  BoardController controller, {
  required String name,
  required String description,
  required bool related,
}) {
  server.registerTool(
    name,
    description: description,
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(
          description: mcpProjectIdParamDescription(whenOmitted: '必填'),
        ),
        'firstCardId': JsonSchema.string(description: '第一张卡片 id'),
        'secondCardId': JsonSchema.string(description: '第二张卡片 id'),
      },
      required: ['projectId', 'firstCardId', 'secondCardId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final projectId = mcpTrimmedString(args['projectId']);
      final firstCardId = mcpTrimmedString(args['firstCardId']);
      final secondCardId = mcpTrimmedString(args['secondCardId']);
      if (projectId == null || firstCardId == null || secondCardId == null) {
        return mcpErrorResult(
          'projectId / firstCardId / secondCardId 均不能为空',
        );
      }
      return runMcpForProject(controller, projectId, (resolvedProjectId) async {
        final error = await controller.setCardsRelated(
          firstCardId: firstCardId,
          secondCardId: secondCardId,
          related: related,
        );
        if (error != null) return mcpErrorResult(error);
        return mcpJsonResult({
          'ok': true,
          'projectId': resolvedProjectId,
          'firstCardId': firstCardId,
          'secondCardId': secondCardId,
          'related': related,
        });
      });
    },
  );
}
