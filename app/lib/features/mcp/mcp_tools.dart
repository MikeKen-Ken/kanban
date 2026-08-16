import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'dispatch/dispatch_claim_next_card.dart';
import 'dispatch/dispatch_private_tools.dart';
import 'mcp_tools_automations.dart';
import 'mcp_tools_cards.dart';
import 'mcp_tools_dispatch.dart';
import 'mcp_tools_attachments.dart';
import 'mcp_tools_labels.dart';
import 'mcp_tools_productivity.dart';
import 'mcp_tools_query.dart';
import 'mcp_tools_relations.dart';
import 'mcp_tools_run_context.dart';
import 'mcp_tools_structure.dart';
import 'mcp_tools_workflow.dart';

/// 向常驻完整 [McpServer] 注册看板工具；所有写入经 [BoardController]。
void registerKanbanMcpTools(
  McpServer server,
  BoardController controller, {
  DispatchScopedEndpointStarter? startScopedEndpoint,
  DispatchScopedEndpointCloser? closeScopedEndpoint,
}) {
  registerKanbanMcpStructureTools(server, controller);
  registerKanbanMcpCardTools(server, controller);
  registerKanbanMcpDispatchTools(
    server,
    controller,
    startScopedEndpoint: startScopedEndpoint,
    closeScopedEndpoint: closeScopedEndpoint,
  );
  registerKanbanMcpWorkflowTools(server, controller);
  registerKanbanMcpRelationTools(server, controller);
  registerKanbanMcpRunContextTools(server, controller);
  registerKanbanMcpAttachmentTools(server, controller);
  registerKanbanMcpQueryTools(server, controller);
  registerKanbanMcpLabelTools(server, controller);
  registerKanbanMcpProductivityTools(server, controller);
  registerKanbanMcpAutomationTools(server, controller);
}
