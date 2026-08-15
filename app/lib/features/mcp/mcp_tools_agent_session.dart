import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_block_card.dart';
import 'mcp_commit_and_submit_card.dart';
import 'mcp_dispatch_card_gate.dart';
import 'mcp_pick_next_card.dart';
import 'mcp_submit_consultation.dart';
import 'mcp_tool_results.dart';

/// Skill 会话可见的看板工具名；须与 [registerKanbanMcpAgentSessionTools] 一致。
const kanbanMcpAgentSessionToolNames = [
  'pick_next_card',
  'submit_consultation',
  'commit_and_submit_card',
  'block_card',
];

/// 调度中拒绝操作非本轮领取的卡片。
CallToolResult? mcpRejectForeignDispatchCard(String cardId) {
  final auth = McpDispatchCardGate.instance.authorizePickedCard(cardId);
  if (auth == null) return null;
  return mcpErrorResult(auth);
}

/// Skill 会话可见的看板工具：取卡、咨询、提交送验、阻塞。
void registerKanbanMcpAgentSessionTools(
  McpServer server,
  BoardController controller,
) {
  server.registerTool(
    'pick_next_card',
    description: '取下一条可实施卡并移入「进行中」。projectId 传项目 UUID。',
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(description: '项目 UUID'),
      },
      required: ['projectId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) {
      return mcpPickNextCard(
        controller,
        projectId: args['projectId'] as String?,
      );
    },
  );

  server.registerTool(
    'submit_consultation',
    description: '提交咨询答复并移入「待验证」。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'responseMarkdown': JsonSchema.string(description: '仅咨询答复 Markdown'),
      },
      required: ['cardId', 'responseMarkdown'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']);
      final responseMarkdown = mcpTrimmedString(args['responseMarkdown']);
      if (cardId == null) return mcpErrorResult('cardId 不能为空');
      if (responseMarkdown == null) {
        return mcpErrorResult('responseMarkdown 不能为空');
      }
      final rejected = mcpRejectForeignDispatchCard(cardId);
      if (rejected != null) return rejected;
      return mcpSubmitConsultation(
        controller,
        cardId: cardId,
        responseMarkdown: responseMarkdown,
      );
    },
  );

  server.registerTool(
    'commit_and_submit_card',
    description: '提交本卡改动并移入「待验证」。只需 cardId；禁止自行 git commit。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '本轮领取的卡片 id'),
      },
      required: ['cardId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']);
      if (cardId == null) return mcpErrorResult('cardId 不能为空');
      return mcpCommitAndSubmitCard(controller, cardId: cardId);
    },
  );

  server.registerTool(
    'block_card',
    description: '将本卡移入「阻塞中」。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'reason': JsonSchema.string(description: '阻塞原因'),
      },
      required: ['cardId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']);
      if (cardId == null) return mcpErrorResult('cardId 不能为空');
      final rejected = mcpRejectForeignDispatchCard(cardId);
      if (rejected != null) return rejected;
      return mcpBlockCard(
        controller,
        cardId: cardId,
        reason: mcpTrimmedString(args['reason']),
      );
    },
  );
}
