import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'dispatch/dispatch_scoped_tools.dart';

/// scoped Agent 会话只暴露三个绑定卡片的工具。
const kanbanMcpAgentSessionToolNames = dispatchScopedAgentToolNames;

void registerKanbanMcpAgentSessionTools(
  McpServer server,
  BoardController controller, {
  required String workerToken,
  required String cardId,
}) {
  registerDispatchScopedAgentTools(
    server,
    controller,
    workerToken: workerToken,
    cardId: cardId,
  );
}
