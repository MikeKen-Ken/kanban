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

/// List only recoverable transactions that match the new Worker's current
/// project/repository binding.
Future<CallToolResult> dispatchListPending({
  required String workerToken,
  DispatchPendingStore? pendingStore,
  McpDispatchCardGate? gate,
}) async {
  final binding =
      _bindingFor(workerToken, gate ?? McpDispatchCardGate.instance);
  if (binding == null) return mcpErrorResult('Invalid Worker token');
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

/// Reauthorize one pending session with a new token from the current full MCP.
Future<CallToolResult> dispatchRecover({
  required String workerToken,
  required String sessionId,
  DispatchPendingStore? pendingStore,
  McpDispatchCardGate? gate,
}) async {
  final binding =
      _bindingFor(workerToken, gate ?? McpDispatchCardGate.instance);
  if (binding == null) return mcpErrorResult('Invalid Worker token');
  final store = pendingStore ?? DispatchPendingStore();
  final record = await store.read(sessionId);
  if (record == null ||
      !_recoverableStatuses.contains(record.status) ||
      !_matchesBinding(record, binding)) {
    return mcpErrorResult(
        'The pending session does not match the current project/repository');
  }
  // Authorization exists only in the active gate. Pending JSON neither stores
  // nor rotates the plaintext token.
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
