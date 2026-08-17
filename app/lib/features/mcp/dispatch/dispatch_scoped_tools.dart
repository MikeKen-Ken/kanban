import 'package:mcp_dart/mcp_dart.dart';

import '../../../controllers/board_controller.dart';
import '../mcp_arg_parsers.dart';
import '../mcp_block_card.dart';
import '../mcp_dispatch_card_gate.dart';
import '../mcp_submit_consultation.dart';
import '../mcp_tool_results.dart';
import 'dispatch_pending_store.dart';
import 'dispatch_ready_to_submit.dart';

const dispatchScopedAgentToolNames = [
  'ready_to_submit',
  'submit_consultation',
  'block_card',
];

void registerDispatchScopedAgentTools(
  McpServer server,
  BoardController controller, {
  required String workerToken,
  required String cardId,
}) {
  server.registerTool(
    'ready_to_submit',
    description: '声明本卡已完成并持久化待收尾数据；不提交 Git、不勾选、不移列。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '本会话绑定的卡片 id'),
        'completedChecklistIds': JsonSchema.array(
          items: JsonSchema.string(),
          description: '本轮明确完成的 checklist id；无则传空数组',
        ),
        'completedFeedbackIds': JsonSchema.array(
          items: JsonSchema.string(),
          description: '本轮明确完成的 feedback id；无则传空数组',
        ),
        'verificationCommands': JsonSchema.array(
          items: JsonSchema.object(
            properties: {
              'executable': JsonSchema.string(),
              'args': JsonSchema.array(items: JsonSchema.string()),
              'cwd': JsonSchema.string(
                description: '仓库内相对工作目录；默认 .',
              ),
              'timeoutMs': JsonSchema.number(
                description: '可选超时毫秒数',
              ),
              'expectedExitCode': JsonSchema.number(),
            },
            required: ['executable', 'args'],
          ),
          description: '已废弃：测试由 Agent 会话内执行，不要传此字段',
        ),
        'manualVerificationReason': JsonSchema.string(
          description: '无法自动验证时的人工验证原因；会话内已跑测试则可省略',
        ),
        'gitRevertCommit': JsonSchema.string(
          description:
              '仅当本卡明确要求撤销指定提交时传其 7–64 位哈希；由 Worker 执行，不要自行运行 git revert',
        ),
      },
      required: [
        'cardId',
        'completedChecklistIds',
        'completedFeedbackIds',
      ],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final requestedCardId = mcpTrimmedString(args['cardId']);
      if (requestedCardId == null) return mcpErrorResult('cardId 不能为空');
      if (requestedCardId != cardId) {
        return mcpErrorResult('该端点只允许操作绑定卡片：$cardId');
      }
      final checklistIds = parseMcpIdList(args['completedChecklistIds']);
      final feedbackIds = parseMcpIdList(args['completedFeedbackIds']);
      if (checklistIds == null || feedbackIds == null) {
        return mcpErrorResult('完成项 id 必须是字符串数组');
      }
      final commands = _parseVerificationCommands(args['verificationCommands']);
      if (commands == null) {
        return mcpErrorResult('verificationCommands 格式无效');
      }
      return dispatchReadyToSubmit(
        controller,
        workerToken: workerToken,
        cardId: requestedCardId,
        completedChecklistIds: checklistIds,
        completedFeedbackIds: feedbackIds,
        verificationCommands: commands,
        manualVerificationReason:
            mcpTrimmedString(args['manualVerificationReason']),
        gitRevertCommit: mcpTrimmedString(args['gitRevertCommit']),
      );
    },
  );

  server.registerTool(
    'submit_consultation',
    description: '提交本会话咨询卡答复并直接移入「待验证」。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(),
        'responseMarkdown': JsonSchema.string(),
      },
      required: ['cardId', 'responseMarkdown'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final requestedCardId = mcpTrimmedString(args['cardId']);
      final response = mcpTrimmedString(args['responseMarkdown']);
      if (requestedCardId == null || response == null) {
        return mcpErrorResult('cardId 与 responseMarkdown 不能为空');
      }
      if (requestedCardId != cardId) {
        return mcpErrorResult('该端点只允许操作绑定卡片：$cardId');
      }
      final rejected = _authorize(workerToken, requestedCardId);
      if (rejected != null) return rejected;
      return mcpSubmitConsultation(
        controller,
        cardId: requestedCardId,
        responseMarkdown: response,
        projectId: McpDispatchCardGate.instance.projectIdForToken(workerToken),
      );
    },
  );

  server.registerTool(
    'block_card',
    description: '将本会话绑定卡片移入「阻塞中」。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(),
        'reason': JsonSchema.string(),
      },
      required: ['cardId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final requestedCardId = mcpTrimmedString(args['cardId']);
      if (requestedCardId == null) return mcpErrorResult('cardId 不能为空');
      if (requestedCardId != cardId) {
        return mcpErrorResult('该端点只允许操作绑定卡片：$cardId');
      }
      final rejected = _authorize(workerToken, requestedCardId);
      if (rejected != null) return rejected;
      return mcpBlockCard(
        controller,
        cardId: requestedCardId,
        projectId: McpDispatchCardGate.instance.projectIdForToken(workerToken),
        reason: mcpTrimmedString(args['reason']),
      );
    },
  );
}

CallToolResult? _authorize(String workerToken, String cardId) {
  final error = McpDispatchCardGate.instance.authorizeScopedCard(
    workerToken: workerToken,
    cardId: cardId,
  );
  return error == null ? null : mcpErrorResult(error);
}

List<DispatchVerificationCommand>? _parseVerificationCommands(dynamic raw) {
  if (raw == null) return const [];
  if (raw is! List) return null;
  final result = <DispatchVerificationCommand>[];
  for (final item in raw) {
    if (item is! Map) return null;
    if (item.containsKey('command')) return null;
    final executable = mcpTrimmedString(item['executable']);
    final args = item['args'];
    final cwd = mcpTrimmedString(item['cwd']) ?? '.';
    if (executable == null ||
        args is! List ||
        args.any((value) => value is! String)) {
      return null;
    }
    final expected = item['expectedExitCode'];
    final timeout = item['timeoutMs'];
    if ((expected != null && expected is! num) ||
        (timeout != null && timeout is! num)) {
      return null;
    }
    final command = DispatchVerificationCommand(
      executable: executable,
      args: args.cast<String>().toList(growable: false),
      cwd: cwd,
      timeoutMs: (timeout as num?)?.toInt(),
      expectedExitCode: (expected as num?)?.toInt() ?? 0,
    );
    if (!command.hasRepoRelativeCwd) return null;
    result.add(command);
  }
  return result;
}
