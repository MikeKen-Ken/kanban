import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import 'mcp_dispatch_card_gate.dart';
import 'mcp_git_commit.dart';
import 'mcp_prepare_card_submission.dart';
import 'mcp_submit_for_verify.dart';
import 'mcp_tool_results.dart';

/// 调度会话收尾：按闸门中的仓库提交（如有）并移入待验证。
Future<CallToolResult> mcpCommitAndSubmitCard(
  BoardController controller, {
  required String cardId,
  String? projectId,
  McpGitRunner? gitRunner,
  McpDispatchCardGate? gate,
}) async {
  final id = cardId.trim();
  if (id.isEmpty) return mcpErrorResult('cardId 不能为空');
  final dispatchGate = gate ?? McpDispatchCardGate.instance;
  final auth = dispatchGate.authorizePickedCard(id);
  if (auth != null) return mcpErrorResult(auth);

  final repoPath = dispatchGate.repoPathForPickedCard(id);
  String? commitRef = dispatchGate.pendingCommitRefForCard(id);
  var completeIncompleteWork = repoPath == null || repoPath.trim().isEmpty;

  if (repoPath != null && repoPath.trim().isNotEmpty) {
    final tree = await inspectMcpGitTree(repoPath, runner: gitRunner);
    if (tree.kind == McpGitTreeKind.dirty) {
      final prepared = await mcpPrepareCardSubmission(
        controller,
        cardId: id,
        projectId: projectId,
      );
      if (prepared.isError == true) return prepared;
      final message = _suggestedCommitMessage(prepared);
      if (message == null || message.trim().isEmpty) {
        return mcpErrorResult('无法生成提交信息');
      }
      final committed = await commitMcpWorkingTree(
        repoPath: repoPath,
        message: message,
        runner: gitRunner,
      );
      if (!committed.ok) {
        return mcpErrorResult(committed.error ?? 'git commit 失败');
      }
      commitRef = committed.commitRef;
      dispatchGate.recordPendingCommitRef(cardId: id, commitRef: commitRef!);
      completeIncompleteWork = true;
    } else if (tree.kind == McpGitTreeKind.clean) {
      final head = await mcpGitShortHead(repoPath, runner: gitRunner);
      final baseline = dispatchGate.baselineCommitRefForCard(id);
      if (commitRef != null && commitRef.isNotEmpty) {
        completeIncompleteWork = true;
      } else if (head != null &&
          baseline != null &&
          head != baseline) {
        commitRef = head;
        dispatchGate.recordPendingCommitRef(cardId: id, commitRef: head);
        completeIncompleteWork = true;
      } else {
        commitRef = head;
        completeIncompleteWork = false;
      }
    } else {
      completeIncompleteWork = true;
    }
  }

  if (!completeIncompleteWork) {
    final card = controller.findCardById(id);
    if (card != null && _cardHasIncompleteWork(card)) {
      return mcpErrorResult(
        '工作区无新的代码提交，且仍有未完成子任务或验证反馈，无法送验',
      );
    }
  }

  return mcpSubmitCardForVerify(
    controller,
    cardId: id,
    projectId: projectId,
    completeAllIncompleteChecklist: completeIncompleteWork,
    completeAllIncompleteFeedback:
        completeIncompleteWork ? null : false,
    commitRef: commitRef,
  );
}

bool _cardHasIncompleteWork(KanbanCard card) {
  return card.checklist.any((item) => !item.completed) ||
      card.verificationFeedback.any((item) => !item.completed);
}

String? _suggestedCommitMessage(CallToolResult prepared) {
  final texts = prepared.content.whereType<TextContent>();
  if (texts.isEmpty) return null;
  try {
    final decoded = jsonDecode(texts.first.text);
    if (decoded is! Map) return null;
    final message = decoded['suggestedCommitMessage'];
    return message is String ? message : null;
  } catch (_) {
    return null;
  }
}
