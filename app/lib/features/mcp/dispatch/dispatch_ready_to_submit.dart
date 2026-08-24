import 'package:mcp_dart/mcp_dart.dart';

import '../../../controllers/board_controller.dart';
import '../mcp_dispatch_card_gate.dart';
import '../mcp_submission_snapshot_store.dart';
import '../mcp_tool_results.dart';
import 'dispatch_pending_store.dart';
import 'dispatch_shell_spans.dart';

Future<CallToolResult> dispatchReadyToSubmit(
  BoardController controller, {
  required String workerToken,
  required String cardId,
  required List<String> completedChecklistIds,
  required List<String> completedFeedbackIds,
  required List<DispatchVerificationCommand> verificationCommands,
  String? manualVerificationReason,
  String? gitRevertCommit,
  McpDispatchCardGate? gate,
  McpSubmissionSnapshotStore? snapshotStore,
  DispatchPendingStore? pendingStore,
  DispatchShellSpanStore? shellSpans,
}) async {
  final token = workerToken.trim();
  final id = cardId.trim();
  final dispatchGate = gate ?? McpDispatchCardGate.instance;
  final auth = dispatchGate.authorizeScopedCard(
    workerToken: token,
    cardId: id,
  );
  if (auth != null) return mcpErrorResult(auth);

  final projectId = dispatchGate.projectIdForToken(token)!;
  final sessionId = dispatchGate.sessionIdForToken(token);
  if (sessionId == null || sessionId.isEmpty) {
    return mcpErrorResult('The dispatch session is missing sessionId');
  }
  final card = await controller.runOnProject(
    projectId,
    () async => controller.findCardById(id),
  );
  if (card == null) return mcpErrorResult('Card not found: $id');
  final snapshot = await (snapshotStore ?? McpSubmissionSnapshotStore()).read(
    projectId: projectId,
    cardId: id,
  );
  if (snapshot == null) {
    return mcpErrorResult(
        'The submission scope frozen at claim time was not found');
  }

  final checklistIds = completedChecklistIds.toSet();
  final feedbackIds = completedFeedbackIds.toSet();
  final unknownChecklist =
      checklistIds.difference(snapshot.incompleteChecklistIds.toSet());
  if (unknownChecklist.isNotEmpty) {
    return mcpErrorResult(
      'completedChecklistIds contains values outside the scope frozen at claim time: ${unknownChecklist.join(', ')}',
    );
  }
  final unknownFeedback =
      feedbackIds.difference(snapshot.incompleteFeedbackIds.toSet());
  if (unknownFeedback.isNotEmpty) {
    return mcpErrorResult(
      'completedFeedbackIds contains values outside the scope frozen at claim time: ${unknownFeedback.join(', ')}',
    );
  }

  final reason = manualVerificationReason?.trim();
  final revertCommit = gitRevertCommit?.trim();
  if (revertCommit != null &&
      (revertCommit.isEmpty ||
          !RegExp(r'^[0-9a-fA-F]{7,64}$').hasMatch(revertCommit))) {
    return mcpErrorResult(
        'gitRevertCommit must be a 7-64 character Git commit hash');
  }
  final hasManualReason = reason != null && reason.isNotEmpty;
  final blocked = (shellSpans ?? DispatchShellSpanStore.instance)
      .readyBlockedReason(sessionId);
  if (blocked != null) return mcpErrorResult(blocked);
  if (verificationCommands.isNotEmpty) {
    return mcpErrorResult(
      'Verification runs in the Agent session. Run tests before ready_to_submit '
      'and do not pass verificationCommands. If automated verification is not '
      'possible, pass only manualVerificationReason.',
    );
  }

  final store = pendingStore ?? DispatchPendingStore();
  final existing = await store.read(sessionId);
  if (existing != null && existing.status != DispatchPendingStatus.declared) {
    return mcpErrorResult(
      'The pending session is already ${existing.status.name} and cannot be declared ready again',
    );
  }
  final record = DispatchPendingRecord(
    sessionId: sessionId,
    workerToken: token,
    projectId: projectId,
    cardId: id,
    status: DispatchPendingStatus.declared,
    completedChecklistIds: checklistIds.toList(growable: false),
    completedFeedbackIds: feedbackIds.toList(growable: false),
    verificationCommands: verificationCommands,
    repoPath: dispatchGate.repoPathForToken(token),
    baselineCommitRef: dispatchGate.baselineCommitRefForCard(id),
    gitRevertCommit: revertCommit,
    manualVerificationReason: hasManualReason ? reason : null,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
  await store.write(record);
  return mcpJsonResult({
    'ok': true,
    'sessionId': sessionId,
    'projectId': projectId,
    'cardId': id,
    'status': record.status.name,
    'completedChecklistIds': record.completedChecklistIds,
    'completedFeedbackIds': record.completedFeedbackIds,
    if (record.gitRevertCommit != null)
      'gitRevertCommit': record.gitRevertCommit,
  });
}
