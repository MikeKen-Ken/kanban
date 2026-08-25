import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:uuid/uuid.dart';

import '../../../controllers/board_controller.dart';
import '../mcp_dispatch_card_gate.dart';
import '../mcp_git_commit.dart';
import '../mcp_pick_next_card.dart';
import '../mcp_tool_results.dart';

typedef DispatchScopedEndpointStarter = Future<String> Function({
  required String workerToken,
  required String cardId,
  required CallToolResult cardContext,
});

/// Atomically claim a card for the Worker. The project comes only from the
/// token binding and is never accepted from the model.
Future<CallToolResult> dispatchClaimNextCard(
  BoardController controller, {
  required String workerToken,
  String? expectedCardId,
  bool effectiveRequireTests = true,
  DispatchScopedEndpointStarter? startScopedEndpoint,
  McpDispatchCardGate? gate,
  McpGitRunner? gitRunner,
}) async {
  final token = workerToken.trim();
  final dispatchGate = gate ?? McpDispatchCardGate.instance;
  final projectId = dispatchGate.projectIdForToken(token);
  if (token.isEmpty || projectId == null) {
    return mcpErrorResult('Invalid Worker token');
  }

  final sessionId = const Uuid().v4();
  if (!dispatchGate.beginAgentSession(token, sessionId: sessionId)) {
    return mcpErrorResult('Unable to start the card-claim session');
  }
  final repoPath = dispatchGate.repoPathForToken(token);
  if (repoPath != null && repoPath.isNotEmpty) {
    dispatchGate.recordBaselineCommitRef(
      token,
      await mcpGitHeadHash(repoPath, runner: gitRunner),
    );
  }

  final claimed = await mcpPickNextCard(
    controller,
    projectId: projectId,
    expectedCardId: expectedCardId,
    dispatchWorkerToken: token,
  );
  if (claimed.isError == true) {
    dispatchGate.closeAgentSession(token);
    return claimed;
  }

  final payload = _jsonPayload(claimed);
  if (payload == null) {
    dispatchGate.closeAgentSession(token);
    return mcpErrorResult('The card-claim result has an invalid format');
  }
  if (payload['found'] != true) {
    dispatchGate.closeAgentSession(token);
    return claimed;
  }
  final cardId = payload['cardId'] as String?;
  if (cardId == null || cardId.isEmpty) {
    dispatchGate.closeAgentSession(token);
    return mcpErrorResult('The card-claim result is missing cardId');
  }

  final frozenContextPayload = <String, dynamic>{
    ...payload,
    'sessionId': sessionId,
    'effectiveRequireTests': effectiveRequireTests,
  };
  final frozenContext = CallToolResult(
    content: [
      TextContent(text: jsonEncode(frozenContextPayload)),
      ...claimed.content.skip(1),
    ],
  );

  String? endpoint;
  if (startScopedEndpoint != null) {
    try {
      endpoint = await startScopedEndpoint(
        workerToken: token,
        cardId: cardId,
        cardContext: frozenContext,
      );
    } on Object catch (error) {
      await _rollbackClaimMove(
        controller,
        projectId: projectId,
        cardId: cardId,
        payload: payload,
      );
      dispatchGate.closeAgentSession(token);
      return mcpErrorResult('Failed to create the scoped Agent MCP: $error');
    }
  }

  final enriched = <String, dynamic>{
    ...frozenContextPayload,
    if (endpoint != null) 'agentEndpointUrl': endpoint,
  };
  return CallToolResult(
    content: [
      TextContent(text: jsonEncode(enriched)),
      ...claimed.content.skip(1),
    ],
  );
}

Future<void> _rollbackClaimMove(
  BoardController controller, {
  required String projectId,
  required String cardId,
  required Map<String, dynamic> payload,
}) async {
  if (payload['movedToDoing'] != true) return;
  final fromColumnId = payload['fromColumnId'] as String?;
  final currentColumnId = payload['columnId'] as String?;
  if (fromColumnId == null || currentColumnId == null) return;
  try {
    await controller.runOnProject(projectId, () async {
      final columns = controller.board?.columns;
      if (columns == null) return;
      var destinationIndex = -1;
      for (var index = 0; index < columns.length; index++) {
        if (columns[index].id == fromColumnId) {
          destinationIndex = index;
          break;
        }
      }
      final destination =
          destinationIndex < 0 ? null : columns[destinationIndex];
      if (destination == null) return;
      await controller.moveCard(
        cardId: cardId,
        fromColumnId: currentColumnId,
        toColumnId: fromColumnId,
        toDisplayIndex: destination.cards.length,
      );
    });
  } on Object {
    // The original endpoint error terminates the round if rollback also fails,
    // preserving the root cause.
  }
}

Map<String, dynamic>? _jsonPayload(CallToolResult result) {
  final texts = result.content.whereType<TextContent>();
  if (texts.isEmpty) return null;
  try {
    final decoded = jsonDecode(texts.first.text);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on Object {
    return null;
  }
}
