import 'package:mcp_dart/mcp_dart.dart';

import '../mcp_dispatch_card_gate.dart';
import '../mcp_tool_results.dart';
import 'dispatch_shell_spans.dart';

Future<CallToolResult> dispatchReportShellSpan({
  required String workerToken,
  required String callId,
  required String command,
  required String phase,
  String? sessionId,
  int? startedAtMs,
  int? endedAtMs,
  int? executionTimeMs,
  int? exitCode,
  DispatchShellSpanStore? store,
  McpDispatchCardGate? gate,
}) async {
  final token = workerToken.trim();
  final id = normalizeDispatchCallId(callId);
  final cmd = command.trim();
  final step = phase.trim().toLowerCase();
  if (token.isEmpty) return mcpErrorResult('workerToken 不能为空');
  if (id.isEmpty) return mcpErrorResult('callId 不能为空');
  if (step != 'start' && step != 'end') {
    return mcpErrorResult('phase 必须是 start 或 end');
  }
  final dispatchGate = gate ?? McpDispatchCardGate.instance;
  final status = dispatchGate.sessionStatus(token);
  if (status == null || !status.sessionOpen) {
    return mcpErrorResult('Worker token 无效或会话未开启');
  }
  final boundSession = status.sessionId;
  if (boundSession == null || boundSession.isEmpty) {
    return mcpErrorResult('调度会话缺少 sessionId');
  }
  final requested = sessionId?.trim();
  if (requested != null && requested.isNotEmpty && requested != boundSession) {
    return mcpErrorResult('sessionId 与当前 Worker 会话不一致');
  }
  (store ?? DispatchShellSpanStore.instance).report(
    sessionId: boundSession,
    callId: id,
    command: cmd,
    phase: step,
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs,
    executionTimeMs: executionTimeMs,
    exitCode: exitCode,
  );
  return mcpJsonResult({
    'ok': true,
    'sessionId': boundSession,
    'callId': id,
    'phase': step,
  });
}
