import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../kanban/next_work_card.dart';
import '../kanban/verify_column.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_set_card_commit_ref.dart';
import 'mcp_submission_snapshot_store.dart';
import 'mcp_tool_results.dart';

/// 将卡片移入「待验证」；可选在移列前完成子任务或更新验证反馈。
///
/// 反馈更新三选一：
/// - [verificationFeedback] 整表替换
/// - [completedFeedbackIds] 勾选指定 id
/// - [completeAllIncompleteFeedback] 勾选全部未完成项
///
/// 若三者皆未传，且卡片仍有未完成验证反馈，则默认勾选全部未完成项（便于只传 cardId）。
Future<CallToolResult> mcpSubmitCardForVerify(
  BoardController controller, {
  required String cardId,
  String? projectId,
  List<ChecklistItem>? verificationFeedback,
  List<String>? completedFeedbackIds,
  bool? completeAllIncompleteFeedback,
  List<String>? completedChecklistIds,
  bool completeAllIncompleteChecklist = false,
  String? commitRef,
  McpSubmissionSnapshotStore? submissionSnapshotStore,
}) async {
  final located = await resolveMcpProjectIdForCard(
    controller,
    cardId: cardId,
    projectId: projectId,
  );
  if (located.error != null) return located.error!;
  final targetProjectId = located.projectId!;

  return runMcpForProject(controller, targetProjectId,
      (resolvedProjectId) async {
    var fromColumnId =
        controller.findColumnIdForCard(cardId) ?? located.columnId;
    if (fromColumnId == null) {
      return mcpErrorResult('未找到卡片所在列：$cardId');
    }

    final modeCount = [
      verificationFeedback != null,
      completedFeedbackIds != null,
      completeAllIncompleteFeedback == true,
    ].where((flag) => flag).length;
    if (modeCount > 1) {
      return mcpErrorResult(
        'verificationFeedback、completedFeedbackIds、'
        'completeAllIncompleteFeedback 只能选其一',
      );
    }

    final card = controller.findCardById(cardId);
    if (card == null) {
      return mcpErrorResult('未找到卡片：$cardId');
    }

    // 优先使用取卡时冻结的范围，避免提前勾选后遗漏本轮已实施子任务。
    final submissionSnapshot =
        await (submissionSnapshotStore ?? McpSubmissionSnapshotStore())
            .read(projectId: resolvedProjectId, cardId: cardId);
    final commitMessage = submissionSnapshot?.suggestedCommitMessage ??
        buildCardCommitMessage(card);

    if (completedChecklistIds != null && completeAllIncompleteChecklist) {
      return mcpErrorResult(
        'completedChecklistIds 与 completeAllIncompleteChecklist 只能选其一',
      );
    }

    List<ChecklistItem>? checklistToApply;
    var completedChecklistCount = 0;
    if (completedChecklistIds != null) {
      final idSet = completedChecklistIds.toSet();
      final unknown = idSet.difference({
        for (final item in card.checklist) item.id,
      });
      if (unknown.isNotEmpty) {
        return mcpErrorResult('子任务 id 不存在：${unknown.join(', ')}');
      }
      completedChecklistCount =
          card.checklist.where((item) => idSet.contains(item.id)).length;
      checklistToApply = [
        for (final item in card.checklist)
          item.completed || idSet.contains(item.id)
              ? item.copyWith(completed: true)
              : item,
      ];
    } else if (completeAllIncompleteChecklist) {
      final incompleteCount =
          card.checklist.where((item) => !item.completed).length;
      if (incompleteCount > 0) {
        completedChecklistCount = incompleteCount;
        checklistToApply = [
          for (final item in card.checklist)
            item.completed ? item : item.copyWith(completed: true),
        ];
      }
    }

    List<ChecklistItem>? feedbackToApply = verificationFeedback;
    if (completedFeedbackIds != null) {
      if (completedFeedbackIds.isNotEmpty &&
          card.verificationFeedback.isEmpty) {
        return mcpErrorResult('卡片没有验证反馈可勾选');
      }
      final idSet = completedFeedbackIds.toSet();
      final unknown = idSet.difference({
        for (final item in card.verificationFeedback) item.id,
      });
      if (unknown.isNotEmpty) {
        return mcpErrorResult('验证反馈 id 不存在：${unknown.join(', ')}');
      }
      feedbackToApply = [
        for (final item in card.verificationFeedback)
          item.completed || idSet.contains(item.id)
              ? item.copyWith(completed: true)
              : item,
      ];
    } else if (completeAllIncompleteFeedback == true ||
        (completeAllIncompleteFeedback != false &&
            verificationFeedback == null &&
            completedFeedbackIds == null &&
            isReworkWorkMode(card))) {
      feedbackToApply = markAllIncompleteFeedbackDone(card);
      if (feedbackToApply == null && completeAllIncompleteFeedback == true) {
        return mcpErrorResult('没有未完成的验证反馈可勾选');
      }
    }

    if (checklistToApply != null || feedbackToApply != null) {
      final updateError = await controller.updateCardFull(
        fromColumnId,
        cardId,
        checklist: checklistToApply,
        verificationFeedback: feedbackToApply,
      );
      if (updateError != null) return mcpErrorResult(updateError);
      fromColumnId = controller.findColumnIdForCard(cardId) ?? fromColumnId;
    }

    final board = controller.board;
    if (board == null) return mcpErrorResult('看板未就绪');

    final verifyColumn = findVerifyColumn(board.columns);
    if (verifyColumn == null) {
      return mcpErrorResult('未找到「待验证」列');
    }

    final wasAlreadyInVerifyColumn = fromColumnId == verifyColumn.id;
    if (!wasAlreadyInVerifyColumn) {
      final moveError = await controller.moveCard(
        cardId: cardId,
        fromColumnId: fromColumnId,
        toColumnId: verifyColumn.id,
        toDisplayIndex: verifyColumn.cards.length,
      );
      if (moveError != null) return mcpErrorResult(moveError);
      fromColumnId = verifyColumn.id;
    }

    final columnIdForCommit =
        controller.findColumnIdForCard(cardId) ?? fromColumnId;
    String? writtenCommitRef;
    if (commitRef != null) {
      final applied = await applyCardCommitRef(
        controller,
        columnId: columnIdForCommit,
        cardId: cardId,
        commitRef: commitRef,
      );
      if (applied.error != null) return mcpErrorResult(applied.error!);
      writtenCommitRef = applied.value;
    }

    final refreshed = controller.findCardById(cardId);
    return mcpJsonResult({
      'ok': true,
      'cardId': cardId,
      'projectId': resolvedProjectId,
      'fromColumnId': fromColumnId,
      'toColumnId': verifyColumn.id,
      'alreadyInVerifyColumn': wasAlreadyInVerifyColumn,
      'suggestedCommitMessage': commitMessage,
      if (completedChecklistIds != null || completeAllIncompleteChecklist)
        'completedChecklistCount': completedChecklistCount,
      if (writtenCommitRef != null) 'commitRef': writtenCommitRef,
      if (writtenCommitRef == null &&
          (refreshed?.commitRef == null || refreshed!.commitRef!.isEmpty))
        'afterGitCommit': {
          'tool': 'set_card_commit_ref',
          'cardId': cardId,
          'hint': 'git commit 后调用，commitRef 传 git rev-parse --short=7 HEAD',
        },
    });
  });
}
