import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_prepare_card_submission.dart';
import 'mcp_submit_consultation.dart';
import 'mcp_tool_results.dart';

/// 注册单卡执行流程中的程序性 MCP 工具。
void registerKanbanMcpWorkflowTools(
  McpServer server,
  BoardController controller,
) {
  server.registerTool(
    'prepare_card_submission',
    description: '只读生成 suggestedCommitMessage 与 suggestedCommitMessageBase64；'
        '不移动卡片。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'projectId': JsonSchema.string(
          description: mcpProjectIdParamDescription(
            whenOmitted: '省略则按 cardId 跨项目定位',
          ),
        ),
      },
      required: ['cardId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: true,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']);
      if (cardId == null) return mcpErrorResult('cardId 不能为空');
      return mcpPrepareCardSubmission(
        controller,
        cardId: cardId,
        projectId: mcpTrimmedString(args['projectId']),
      );
    },
  );

  server.registerTool(
    'submit_consultation',
    description: '将 responseMarkdown 追加到原备注并移入「待验证」。'
        '仅用于带 consultation 标签的卡片；无需先调用 update_card。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'responseMarkdown': JsonSchema.string(description: '仅咨询答复 Markdown'),
        'projectId': JsonSchema.string(
          description: mcpProjectIdParamDescription(
            whenOmitted: '省略则按 cardId 跨项目定位',
          ),
        ),
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
      return mcpSubmitConsultation(
        controller,
        cardId: cardId,
        responseMarkdown: responseMarkdown,
        projectId: mcpTrimmedString(args['projectId']),
      );
    },
  );
}
