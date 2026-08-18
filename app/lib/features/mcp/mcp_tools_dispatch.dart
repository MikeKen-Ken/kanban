import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'dispatch/dispatch_claim_next_card.dart';
import 'dispatch/dispatch_private_tools.dart';
import 'mcp_pick_next_card.dart';

/// 注册 Worker 私有批次协调工具；完整 MCP 常驻，scoped 端点按 claim 创建。
void registerKanbanMcpDispatchTools(
  McpServer server,
  BoardController controller, {
  DispatchScopedEndpointStarter? startScopedEndpoint,
  DispatchScopedEndpointCloser? closeScopedEndpoint,
}) {
  server.registerTool(
    'peek_next_card',
    description: '只读判断是否还有待办、待返工或进行中未完成卡片；不领取、不移动卡片。',
    inputSchema: JsonSchema.object(properties: {
      'projectId': JsonSchema.string(description: '项目 UUID'),
    }),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) => mcpPeekNextCard(
      controller,
      projectId: args['projectId'] as String?,
    ),
  );
  registerDispatchPrivateTools(
    server,
    controller,
    startScopedEndpoint: startScopedEndpoint,
    closeScopedEndpoint: closeScopedEndpoint,
  );
}
