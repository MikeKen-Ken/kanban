import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../kanban/next_work_card.dart';
import '../kanban/verify_column.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

/// 取下一条可实施卡，并自动移入「进行中」。
///
/// 选取规则与 [pickNextWorkCard] 一致：优先「待办」最新未完成卡，否则「待返工」。
Future<CallToolResult> mcpPickNextCard(
  BoardController controller, {
  String? projectId,
}) {
  return runMcpForProject(controller, projectId, (resolvedProjectId) async {
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
    return mcpJsonResult({
      'found': true,
      'projectId': resolvedProjectId,
      'cardId': card.id,
      'sourceColumn': picked.sourceColumn,
      'fromColumnId': fromColumnId,
      'columnId': columnId,
      'columnTitle': columnTitle,
      'movedToDoing': !alreadyInDoing && !isReworkSource,
      'workMode': rework ? 'rework' : 'normal',
      'workItems': buildCardWorkItems(card),
      'suggestedCommitMessage': buildCardCommitMessage(card),
    });
  });
}
