import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../kanban/next_work_card.dart';
import '../kanban/verify_column.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_dispatch_card_gate.dart';
import 'mcp_submission_snapshot_store.dart';
import 'mcp_tool_results.dart';
import 'mcp_work_scope_result.dart';

/// 只读判断当前项目是否还有可实施卡片；不移动、不领取、不创建快照。
Future<CallToolResult> mcpPeekNextCard(
  BoardController controller, {
  String? projectId,
}) {
  return runMcpForProject(controller, projectId, (resolvedProjectId) async {
    final board = controller.board;
    if (board == null) return mcpErrorResult('看板未就绪');
    final next = pickNextWorkCard(board);
    return mcpJsonResult({
      'found': next != null,
      'projectId': resolvedProjectId,
      if (next != null) ...{
        'sourceColumn': next.sourceColumn,
        'cardId': next.card.id,
        ...next.card.agentDispatchOverridePayload(),
      },
    });
  });
}

/// 取下一条可实施卡，并自动移入「进行中」。
///
/// 选取规则与 [pickNextWorkCard] 一致：待返工，其次进行中滞留卡，最后待办。
/// 默认 [includeWorkItems]=true，一次返回实施范围与附件内容；仅 peek 时可传 false。
Future<CallToolResult> mcpPickNextCard(
  BoardController controller, {
  String? projectId,
  bool includeWorkItems = true,
  String? expectedCardId,
  String? dispatchWorkerToken,
  McpSubmissionSnapshotStore? submissionSnapshotStore,
}) {
  final requested = mcpTrimmedString(projectId);
  if (requested == null && McpDispatchCardGate.instance.openSessionCount > 1) {
    return Future.value(mcpErrorResult(
      '多个 Agent 调度批次并行时，pick_next_card 必须传入 projectId',
    ));
  }
  final boundProjectId =
      requested ?? McpDispatchCardGate.instance.singleOpenSessionProjectId;
  return runMcpForProject(controller, boundProjectId,
      (resolvedProjectId) async {
    final gate = McpDispatchCardGate.instance;
    final permission = gate.authorizePick(
      resolvedProjectId,
      workerToken: dispatchWorkerToken,
    );
    switch (permission) {
      case McpDispatchPickPermission.allowed:
        break;
      case McpDispatchPickPermission.dispatchLocked:
        return mcpErrorResult(
          '该项目正由 Agent 调度锁定，完整 MCP 不得调用 pick_next_card',
        );
      case McpDispatchPickPermission.sessionNotOpen:
        return mcpErrorResult(
          'Agent 调度批次尚未开启本轮 claim，禁止领取卡片',
        );
      case McpDispatchPickPermission.alreadyClaimed:
        return mcpErrorResult(
          '本轮 Worker claim 已领取卡片；请完成当前卡片并结束会话',
        );
    }
    final board = controller.board;
    if (board == null) {
      gate.releasePickAttempt(
        resolvedProjectId,
        workerToken: dispatchWorkerToken,
      );
      return mcpErrorResult('看板未就绪');
    }

    final picked = pickNextWorkCard(board);
    if (picked == null) {
      gate.releasePickAttempt(
        resolvedProjectId,
        workerToken: dispatchWorkerToken,
      );
      return mcpJsonResult({
        'found': false,
        'projectId': resolvedProjectId,
        'reason': '待办、待返工与进行中均无未完成卡片',
      });
    }

    final card = picked.card;
    final expected = mcpTrimmedString(expectedCardId);
    if (expected != null && card.id != expected) {
      gate.releasePickAttempt(
        resolvedProjectId,
        workerToken: dispatchWorkerToken,
      );
      return mcpErrorResult(
        '下一张卡片已漂移：expectedCardId=$expected，actualCardId=${card.id}',
      );
    }
    final fromColumnId = picked.column.id;
    final doingColumn = findDoingColumn(board.columns);
    if (doingColumn == null) {
      gate.releasePickAttempt(
        resolvedProjectId,
        workerToken: dispatchWorkerToken,
      );
      return mcpErrorResult('未找到「进行中」列');
    }

    var columnId = fromColumnId;
    var columnTitle = picked.column.title;
    final isReworkSource =
        picked.sourceColumn == KanbanBoard.defaultReworkColumnTitle;
    final alreadyInDoing = fromColumnId == doingColumn.id;
    if (!alreadyInDoing && !isReworkSource) {
      final moveError = await controller.moveCard(
        cardId: card.id,
        fromColumnId: fromColumnId,
        toColumnId: doingColumn.id,
        toDisplayIndex: doingColumn.cards.length,
      );
      if (moveError != null) {
        gate.releasePickAttempt(
          resolvedProjectId,
          workerToken: dispatchWorkerToken,
        );
        return mcpErrorResult(moveError);
      }
      columnId = doingColumn.id;
      columnTitle = doingColumn.title;
    }

    gate.recordPickedCard(
      projectId: resolvedProjectId,
      cardId: card.id,
      workerToken: dispatchWorkerToken,
    );
    final rework = isReworkWorkMode(card);
    await (submissionSnapshotStore ?? McpSubmissionSnapshotStore()).write(
      McpSubmissionSnapshot(
        projectId: resolvedProjectId,
        cardId: card.id,
        workMode: rework ? 'rework' : 'normal',
        suggestedCommitMessage: buildCardCommitMessage(card),
        incompleteChecklistIds: [
          for (final item in card.checklist)
            if (!item.completed) item.id,
        ],
        incompleteFeedbackIds: [
          for (final item in card.verificationFeedback)
            if (!item.completed) item.id,
        ],
        capturedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final payload = <String, dynamic>{
      'found': true,
      'projectId': resolvedProjectId,
      'cardId': card.id,
      if (controller.projectSettings.agentMcpTags.isNotEmpty)
        'projectMcpTags': controller.projectSettings.agentMcpTags,
      'sourceColumn': picked.sourceColumn,
      'fromColumnId': fromColumnId,
      'columnId': columnId,
      'columnTitle': columnTitle,
      'movedToDoing': !alreadyInDoing && !isReworkSource,
      'workMode': rework ? 'rework' : 'normal',
      ...card.agentDispatchOverridePayload(),
      if (card.commitRef != null && card.commitRef!.isNotEmpty)
        'commitRef': card.commitRef,
    };
    if (!includeWorkItems) {
      return mcpJsonResult(payload);
    }
    return mcpWorkScopeResult(
      controller: controller,
      projectId: resolvedProjectId,
      card: card,
      basePayload: payload,
    );
  });
}
