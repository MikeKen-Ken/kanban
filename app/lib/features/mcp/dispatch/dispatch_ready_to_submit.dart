import 'package:mcp_dart/mcp_dart.dart';

import '../../../controllers/board_controller.dart';
import '../mcp_dispatch_card_gate.dart';
import '../mcp_submission_snapshot_store.dart';
import '../mcp_tool_results.dart';
import 'dispatch_pending_store.dart';
import 'dispatch_verification_policy.dart';

Future<CallToolResult> dispatchReadyToSubmit(
  BoardController controller, {
  required String workerToken,
  required String cardId,
  required List<String> completedChecklistIds,
  required List<String> completedFeedbackIds,
  required List<DispatchVerificationCommand> verificationCommands,
  String? manualVerificationReason,
  McpDispatchCardGate? gate,
  McpSubmissionSnapshotStore? snapshotStore,
  DispatchPendingStore? pendingStore,
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
    return mcpErrorResult('调度会话缺少 sessionId');
  }
  final card = await controller.runOnProject(
    projectId,
    () async => controller.findCardById(id),
  );
  if (card == null) return mcpErrorResult('未找到卡片：$id');
  final snapshot = await (snapshotStore ?? McpSubmissionSnapshotStore()).read(
    projectId: projectId,
    cardId: id,
  );
  if (snapshot == null) return mcpErrorResult('未找到 claim 时冻结的提交范围');

  final checklistIds = completedChecklistIds.toSet();
  final feedbackIds = completedFeedbackIds.toSet();
  final unknownChecklist =
      checklistIds.difference(snapshot.incompleteChecklistIds.toSet());
  if (unknownChecklist.isNotEmpty) {
    return mcpErrorResult(
      'completedChecklistIds 超出 claim 冻结范围：${unknownChecklist.join(', ')}',
    );
  }
  final unknownFeedback =
      feedbackIds.difference(snapshot.incompleteFeedbackIds.toSet());
  if (unknownFeedback.isNotEmpty) {
    return mcpErrorResult(
      'completedFeedbackIds 超出 claim 冻结范围：${unknownFeedback.join(', ')}',
    );
  }

  final reason = manualVerificationReason?.trim();
  final hasManualReason = reason != null && reason.isNotEmpty;
  if (verificationCommands.isEmpty == !hasManualReason) {
    return mcpErrorResult(
      'verificationCommands 与 manualVerificationReason 必须且只能提供一种',
    );
  }
  for (final command in verificationCommands) {
    if (command.executable.trim().isEmpty) {
      return mcpErrorResult('verificationCommands.executable 不能为空');
    }
    if (!command.hasRepoRelativeCwd) {
      return mcpErrorResult('verificationCommands.cwd 必须是仓库内相对路径');
    }
    if (command.timeoutMs != null && command.timeoutMs! <= 0) {
      return mcpErrorResult('verificationCommands.timeoutMs 必须大于 0');
    }
    final policyError = dispatchVerificationPolicyError(command);
    if (policyError != null) return mcpErrorResult(policyError);
  }

  final store = pendingStore ?? DispatchPendingStore();
  final existing = await store.read(sessionId);
  if (existing != null && existing.status != DispatchPendingStatus.declared) {
    return mcpErrorResult(
      'pending 已进入 ${existing.status.name}，不能重新声明 ready',
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
  });
}
