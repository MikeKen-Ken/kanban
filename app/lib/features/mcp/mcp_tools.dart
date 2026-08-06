import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_tools_automations.dart';
import 'mcp_tools_cards.dart';
import 'mcp_tools_labels.dart';
import 'mcp_tools_productivity.dart';
import 'mcp_tools_query.dart';
import 'mcp_tools_structure.dart';

/// 向 [McpServer] 注册看板工具；所有写入经 [BoardController]。
void registerKanbanMcpTools(McpServer server, BoardController controller) {
  registerKanbanMcpStructureTools(server, controller);
  registerKanbanMcpCardTools(server, controller);
  registerKanbanMcpQueryTools(server, controller);
  registerKanbanMcpLabelTools(server, controller);
  registerKanbanMcpProductivityTools(server, controller);
  registerKanbanMcpAutomationTools(server, controller);
}
