import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;

import '../mcp_dispatch_card_gate.dart';
import '../mcp_tool_results.dart';
import 'dispatch_pending_store.dart';

const _recoverableStatuses = {
  DispatchPendingStatus.declared,
  DispatchPendingStatus.validated,
  DispatchPendingStatus.committing,
  DispatchPendingStatus.committed,
};

/// 只列出与新 Worker 当前 project/repo 绑定一致的可恢复事务。
Future<CallToolResult> dispatchListPending({
  required String workerToken,
  DispatchPendingStore? pendingStore,
  McpDispatchCardGate? gate,
}) async {
  final binding =
      _bindingFor(workerToken, gate ?? McpDispatchCardGate.instance);
  if (binding == null) return mcpErrorResult('Worker token 无效');
  final records = await (pendingStore ?? DispatchPendingStore()).list();
  return mcpJsonResult({
    'ok': true,
    'pending': [
      for (final record in records)
        if (_recoverableStatuses.contains(record.status) &&
            _matchesBinding(record, binding))
          record.toJson(),
    ],
  });
}

/// 使用当前完整 MCP 的新 token 重新授权单个 pending 会话。
Future<CallToolResult> dispatchRecover({
  required String workerToken,
  required String sessionId,
  DispatchPendingStore? pendingStore,
  McpDispatchCardGate? gate,
}) async {
  final binding =
      _bindingFor(workerToken, gate ?? McpDispatchCardGate.instance);
  if (binding == null) return mcpErrorResult('Worker token 无效');
  final store = pendingStore ?? DispatchPendingStore();
  final record = await store.read(sessionId);
  if (record == null ||
      !_recoverableStatuses.contains(record.status) ||
      !_matchesBinding(record, binding)) {
    return mcpErrorResult('pending 会话与当前 project/repo 不匹配');
  }
  // 权限只存在于活跃 gate；pending JSON 不再保存或轮换明文 token。
  return mcpJsonResult(record.toJson());
}

({String projectId, String? repoPath})? _bindingFor(
  String workerToken,
  McpDispatchCardGate gate,
) {
  final token = workerToken.trim();
  final projectId = gate.projectIdForToken(token);
  if (token.isEmpty || projectId == null) return null;
  return (
    projectId: projectId,
    repoPath: _normalizeRepo(gate.repoPathForToken(token)),
  );
}

bool _matchesBinding(
  DispatchPendingRecord record,
  ({String projectId, String? repoPath}) binding,
) =>
    record.projectId == binding.projectId &&
    _normalizeRepo(record.repoPath) == binding.repoPath;

String? _normalizeRepo(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final normalized = p.normalize(p.absolute(trimmed));
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}
