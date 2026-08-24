import 'package:mcp_dart/mcp_dart.dart';

import '../../../controllers/board_controller.dart';
import '../mcp_block_card.dart';
import '../mcp_dispatch_card_gate.dart';
import '../mcp_tool_results.dart';
import 'dispatch_pending_store.dart';

/// Record a failed round. When [block] is true, move the claimed card to the
/// blocked column.
Future<CallToolResult> dispatchFailOrBlock(
  BoardController controller, {
  required String workerToken,
  required String sessionId,
  required String reason,
  required bool block,
  DispatchPendingStore? pendingStore,
  McpDispatchCardGate? gate,
}) async {
  final store = pendingStore ?? DispatchPendingStore();
  final dispatchGate = gate ?? McpDispatchCardGate.instance;
  var record = await store.read(sessionId);
  if (record == null) {
    final status = dispatchGate.sessionStatus(workerToken);
    if (status?.sessionId != sessionId ||
        status?.cardId == null ||
        status?.projectId == null) {
      return mcpErrorResult('No pending session was found for this Worker');
    }
    record = DispatchPendingRecord(
      sessionId: sessionId,
      workerToken: workerToken,
      projectId: status!.projectId!,
      cardId: status.cardId!,
      status: DispatchPendingStatus.failed,
      completedChecklistIds: const [],
      completedFeedbackIds: const [],
      verificationCommands: const [],
      repoPath: dispatchGate.repoPathForToken(workerToken),
      baselineCommitRef: status.baselineCommitRef,
      error: reason,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
  if (!dispatchGate.authorizesPending(
    workerToken: workerToken,
    projectId: record.projectId,
    repoPath: record.repoPath,
  )) {
    return mcpErrorResult('No pending session was found for this Worker');
  }
  if (block) {
    final blocked = await mcpBlockCard(
      controller,
      cardId: record.cardId,
      projectId: record.projectId,
      reason: reason,
    );
    if (blocked.isError == true) return blocked;
  }
  final failed = record.copyWith(
    status: DispatchPendingStatus.failed,
    error: reason,
  );
  await store.write(failed);
  return mcpJsonResult(failed.toJson());
}
