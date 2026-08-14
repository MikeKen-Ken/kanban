import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../kanban/next_work_card.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_submission_snapshot_store.dart';
import 'mcp_tool_results.dart';

/// 只读生成卡片提交信息，不移动卡片或勾选验证反馈。
Future<CallToolResult> mcpPrepareCardSubmission(
  BoardController controller, {
  required String cardId,
  String? projectId,
  McpSubmissionSnapshotStore? submissionSnapshotStore,
}) async {
  final located = await resolveMcpProjectIdForCard(
    controller,
    cardId: cardId,
    projectId: projectId,
  );
  if (located.error != null) return located.error!;

  return runMcpForProject(controller, located.projectId!,
      (resolvedProjectId) async {
    final card = controller.findCardById(cardId);
    if (card == null) return mcpErrorResult('未找到卡片：$cardId');

    final snapshot =
        await (submissionSnapshotStore ?? McpSubmissionSnapshotStore())
            .read(projectId: resolvedProjectId, cardId: cardId);
    final workMode =
        snapshot?.workMode ?? (isReworkWorkMode(card) ? 'rework' : 'normal');
    final rework = workMode == 'rework';
    final suggestedCommitMessage =
        snapshot?.suggestedCommitMessage ?? buildCardCommitMessage(card);
    return mcpJsonResult({
      'ok': true,
      'cardId': cardId,
      'projectId': resolvedProjectId,
      'workMode': workMode,
      'suggestedCommitMessage': suggestedCommitMessage,
      'suggestedCommitMessageBase64':
          base64Encode(utf8.encode(suggestedCommitMessage)),
      if (rework)
        'incompleteFeedbackIds': snapshot?.incompleteFeedbackIds ??
            [
              for (final item in card.verificationFeedback)
                if (!item.completed) item.id,
            ],
    });
  });
}
