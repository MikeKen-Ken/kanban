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
      if (next != null) 'sourceColumn': next.sourceColumn,
    });
  });
}

/// 取下一条可实施卡，并自动移入「进行中」。
///
/// 选取规则与 [pickNextWorkCard] 一致：优先「待返工」最新未完成卡，否则「待办」。
/// 默认 [includeWorkItems]=true，一次返回实施范围与附件内容；仅 peek 时可传 false。
Future<CallToolResult> mcpPickNextCard(
  BoardController controller, {
  String? projectId,
  bool includeWorkItems = true,
  McpSubmissionSnapshotStore? submissionSnapshotStore,
}) {
  final requested = mcpTrimmedString(projectId);
  if (requested == null &&
      McpDispatchCardGate.instance.openSessionCount > 1) {
    return Future.value(mcpErrorResult(
      '多个 Agent 调度批次并行时，pick_next_card 必须传入 projectId',
    ));
  }
  final boundProjectId =
      requested ?? McpDispatchCardGate.instance.singleOpenSessionProjectId;
  return runMcpForProject(controller, boundProjectId, (resolvedProjectId) async {
    final permission =
        McpDispatchCardGate.instance.authorizePick(resolvedProjectId);
    switch (permission) {
      case McpDispatchPickPermission.allowed:
        break;
      case McpDispatchPickPermission.sessionNotOpen:
        return mcpErrorResult(
          'Agent 调度批次尚未由 Worker 开启本轮会话，禁止领取卡片',
        );
      case McpDispatchPickPermission.alreadyClaimed:
        return mcpErrorResult(
          '本轮 Agent 会话已经调用过 pick_next_card；请完成当前卡片并结束会话',
        );
    }
    final board = controller.board;
    if (board == null) return mcpErrorResult('看板未就绪');

    final picked = pickNextWorkCard(board);
    if (picked == null) {
      return mcpJsonResult({
        'found': false,
        'projectId': resolvedProjectId,
        'reason': '待办与待返工均无未完成卡片',
      });
    }

    final card = picked.card;
    final fromColumnId = picked.column.id;
    final doingColumn = findDoingColumn(board.columns);
    if (doingColumn == null) {
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
      if (moveError != null) return mcpErrorResult(moveError);
      columnId = doingColumn.id;
      columnTitle = doingColumn.title;
    }

    final rework = isReworkWorkMode(card);
    await (submissionSnapshotStore ?? McpSubmissionSnapshotStore()).write(
      McpSubmissionSnapshot(
        projectId: resolvedProjectId,
        cardId: card.id,
        workMode: rework ? 'rework' : 'normal',
        suggestedCommitMessage: buildCardCommitMessage(card),
        incompleteFeedbackIds: [
          if (rework)
            for (final item in card.verificationFeedback)
              if (!item.completed) item.id,
        ],
        capturedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    McpDispatchCardGate.instance.recordPickedCard(
      projectId: resolvedProjectId,
      cardId: card.id,
    );
    final payload = <String, dynamic>{
      'found': true,
      'projectId': resolvedProjectId,
      'cardId': card.id,
      'sourceColumn': picked.sourceColumn,
      'fromColumnId': fromColumnId,
      'columnId': columnId,
      'columnTitle': columnTitle,
      'movedToDoing': !alreadyInDoing && !isReworkSource,
      'workMode': rework ? 'rework' : 'normal',
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
