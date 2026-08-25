import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'dispatch/dispatch_scoped_tools.dart';

/// scoped Agent 会话只暴露一个冻结上下文读取工具与三个收尾工具。
const kanbanMcpAgentSessionToolNames = dispatchScopedAgentToolNames;

void registerKanbanMcpAgentSessionTools(
  McpServer server,
  BoardController controller, {
  required String workerToken,
  required String cardId,
  required CallToolResult cardContext,
}) {
  registerDispatchScopedAgentTools(
    server,
    controller,
    workerToken: workerToken,
    cardId: cardId,
    cardContext: cardContext,
  );
}
