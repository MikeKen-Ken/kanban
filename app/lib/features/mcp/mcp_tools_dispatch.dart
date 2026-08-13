import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_dispatch_card_gate.dart';
import 'mcp_pick_next_card.dart';
import 'mcp_tool_results.dart';

/// 注册 Agent Worker 的批次协调工具。
///
/// Worker token 不进入 AI 提示；AI 只会按 Skill 使用普通 `pick_next_card`。
void registerKanbanMcpDispatchTools(
  McpServer server,
  BoardController controller,
) {
  server.registerTool(
    'peek_next_card',
    description: '只读判断是否还有待办或待返工卡片；不领取、不移动卡片。',
    inputSchema: JsonSchema.object(properties: {
      'projectId':
          JsonSchema.string(description: mcpProjectIdParamDescription()),
    }),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) => mcpPeekNextCard(
      controller,
      projectId: args['projectId'] as String?,
    ),
  );

  server.registerTool(
    'dispatch_begin_agent_session',
    description: 'Agent 调度 Worker 内部工具：开启一轮新的单卡会话。',
    inputSchema: JsonSchema.object(
      properties: {'workerToken': JsonSchema.string()},
      required: ['workerToken'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final token = mcpTrimmedString(args['workerToken']);
      if (token == null ||
          !McpDispatchCardGate.instance.beginAgentSession(token)) {
        return mcpErrorResult('Worker token 无效，无法开启单卡会话');
      }
      return mcpJsonResult({'ok': true});
    },
  );

  server.registerTool(
    'dispatch_agent_session_status',
    description: 'Agent 调度 Worker 内部工具：读取本轮领取的卡片 id。',
    inputSchema: JsonSchema.object(
      properties: {'workerToken': JsonSchema.string()},
      required: ['workerToken'],
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final token = mcpTrimmedString(args['workerToken']);
      final status = token == null
          ? null
          : McpDispatchCardGate.instance.sessionStatus(token);
      if (status == null) return mcpErrorResult('Worker token 无效');
      return mcpJsonResult(status.toJson());
    },
  );
}
