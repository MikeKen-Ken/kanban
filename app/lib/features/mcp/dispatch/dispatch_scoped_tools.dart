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
    description:
        'Declare this card complete and persist pending finalization data. This does not commit Git changes, check items, or move the card.',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId':
            JsonSchema.string(description: 'Card id bound to this session'),
        'completedChecklistIds': JsonSchema.array(
          items: JsonSchema.string(),
          description:
              'Checklist ids explicitly completed in this round; pass an empty array when there are none',
        ),
        'completedFeedbackIds': JsonSchema.array(
          items: JsonSchema.string(),
          description:
              'Feedback ids explicitly completed in this round; pass an empty array when there are none',
        ),
        'verificationCommands': JsonSchema.array(
          items: JsonSchema.object(
            properties: {
              'executable': JsonSchema.string(),
              'args': JsonSchema.array(items: JsonSchema.string()),
              'cwd': JsonSchema.string(
                description:
                    'Repository-relative working directory; defaults to .',
              ),
              'timeoutMs': JsonSchema.number(
                description: 'Optional timeout in milliseconds',
              ),
              'expectedExitCode': JsonSchema.number(),
            },
            required: ['executable', 'args'],
          ),
          description:
              'Deprecated: tests run in the Agent session; do not pass this field',
        ),
        'manualVerificationReason': JsonSchema.string(
          description:
              'Reason for manual verification when automated verification is unavailable; omit when tests ran in the session',
        ),
        'gitRevertCommit': JsonSchema.string(
          description:
              'Pass a 7-64 character commit hash only when this card explicitly requires reverting that commit. The Worker performs the revert; do not run git revert yourself.',
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
      if (requestedCardId == null) {
        return mcpErrorResult('cardId cannot be empty');
      }
      if (requestedCardId != cardId) {
        return mcpErrorResult(
            'This endpoint can operate only on its bound card: $cardId');
      }
      final checklistIds = parseMcpIdList(args['completedChecklistIds']);
      final feedbackIds = parseMcpIdList(args['completedFeedbackIds']);
      if (checklistIds == null || feedbackIds == null) {
        return mcpErrorResult('Completed item ids must be string arrays');
      }
      final commands = _parseVerificationCommands(args['verificationCommands']);
      if (commands == null) {
        return mcpErrorResult('verificationCommands has an invalid format');
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
    description:
        'Submit the consultation response for this session and move the card directly to Verify.',
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
        return mcpErrorResult('cardId and responseMarkdown cannot be empty');
      }
      if (requestedCardId != cardId) {
        return mcpErrorResult(
            'This endpoint can operate only on its bound card: $cardId');
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
    description: 'Move the card bound to this session to Blocked.',
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
      if (requestedCardId == null) {
        return mcpErrorResult('cardId cannot be empty');
      }
      if (requestedCardId != cardId) {
        return mcpErrorResult(
            'This endpoint can operate only on its bound card: $cardId');
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
