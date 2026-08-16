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
});

/// Worker 私有原子领卡：项目只能来自 token 绑定，不接受模型传入的项目。
Future<CallToolResult> dispatchClaimNextCard(
  BoardController controller, {
  required String workerToken,
  String? expectedCardId,
  DispatchScopedEndpointStarter? startScopedEndpoint,
  McpDispatchCardGate? gate,
  McpGitRunner? gitRunner,
}) async {
  final token = workerToken.trim();
  final dispatchGate = gate ?? McpDispatchCardGate.instance;
  final projectId = dispatchGate.projectIdForToken(token);
  if (token.isEmpty || projectId == null) {
    return mcpErrorResult('Worker token 无效');
  }

  final sessionId = const Uuid().v4();
  if (!dispatchGate.beginAgentSession(token, sessionId: sessionId)) {
    return mcpErrorResult('无法开启领卡会话');
  }
  final repoPath = dispatchGate.repoPathForToken(token);
  if (repoPath != null && repoPath.isNotEmpty) {
    dispatchGate.recordBaselineCommitRef(
      token,
      await mcpGitShortHead(repoPath, runner: gitRunner),
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
    return mcpErrorResult('领卡结果格式无效');
  }
  if (payload['found'] != true) {
    dispatchGate.closeAgentSession(token);
    return claimed;
  }
  final cardId = payload['cardId'] as String?;
  if (cardId == null || cardId.isEmpty) {
    dispatchGate.closeAgentSession(token);
    return mcpErrorResult('领卡结果缺少 cardId');
  }

  String? endpoint;
  if (startScopedEndpoint != null) {
    try {
      endpoint = await startScopedEndpoint(
        workerToken: token,
        cardId: cardId,
      );
    } on Object catch (error) {
      await _rollbackClaimMove(
        controller,
        projectId: projectId,
        cardId: cardId,
        payload: payload,
      );
      dispatchGate.closeAgentSession(token);
      return mcpErrorResult('创建 scoped Agent MCP 失败：$error');
    }
  }

  final enriched = <String, dynamic>{
    ...payload,
    'sessionId': sessionId,
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
    // 回滚失败由原始 endpoint 错误统一终止本轮，避免覆盖根因。
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
