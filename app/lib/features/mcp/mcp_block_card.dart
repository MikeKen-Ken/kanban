import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../kanban/verify_column.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

/// 将阻塞原因追加到备注末尾。
String appendBlockReasonToDescription(String? description, String reason) {
  final trimmedReason = reason.trim();
  final blockNote = '阻塞原因：$trimmedReason';
  final existing = description?.trimRight() ?? '';
  if (existing.isEmpty) return blockNote;
  return '$existing\n\n$blockNote';
}

/// 将卡片移入「阻塞中」（实施失败 / 无法继续时使用）。
///
/// 只需 [cardId]；省略 [projectId] 时按卡片跨项目定位。
/// 传入 [reason] 时追加到备注末尾（`阻塞原因：…`）。
Future<CallToolResult> mcpBlockCard(
  BoardController controller, {
  required String cardId,
  String? projectId,
  String? reason,
}) async {
  final located = await resolveMcpProjectIdForCard(
    controller,
    cardId: cardId,
    projectId: projectId,
  );
  if (located.error != null) return located.error!;
  final targetProjectId = located.projectId!;

  return runMcpForProject(controller, targetProjectId, (resolvedProjectId) async {
    final fromColumnId =
        controller.findColumnIdForCard(cardId) ?? located.columnId;
    if (fromColumnId == null) {
      return mcpErrorResult('未找到卡片所在列：$cardId');
    }

    final board = controller.board;
    if (board == null) return mcpErrorResult('看板未就绪');

    final blockedColumn = findBlockedColumn(board.columns);
    if (blockedColumn == null) {
      return mcpErrorResult('未找到「阻塞中」列');
    }

    final trimmedReason = reason?.trim();
    String? descriptionAfterReason;
    if (trimmedReason != null && trimmedReason.isNotEmpty) {
      final card = controller.findCardById(cardId);
      if (card == null) return mcpErrorResult('未找到卡片：$cardId');
      descriptionAfterReason =
          appendBlockReasonToDescription(card.description, trimmedReason);
      final updateError = await controller.updateCardFull(
        fromColumnId,
        cardId,
        description: descriptionAfterReason,
      );
      if (updateError != null) return mcpErrorResult(updateError);
    }

    if (fromColumnId == blockedColumn.id) {
      return mcpJsonResult({
        'ok': true,
        'cardId': cardId,
        'projectId': resolvedProjectId,
        'fromColumnId': fromColumnId,
        'toColumnId': blockedColumn.id,
        'alreadyInBlockedColumn': true,
        if (descriptionAfterReason != null)
          'description': descriptionAfterReason,
      });
    }

    final moveError = await controller.moveCard(
      cardId: cardId,
      fromColumnId: fromColumnId,
      toColumnId: blockedColumn.id,
      toDisplayIndex: blockedColumn.cards.length,
    );
    if (moveError != null) return mcpErrorResult(moveError);

    return mcpJsonResult({
      'ok': true,
      'cardId': cardId,
      'projectId': resolvedProjectId,
      'fromColumnId': fromColumnId,
      'toColumnId': blockedColumn.id,
      'alreadyInBlockedColumn': false,
      if (descriptionAfterReason != null) 'description': descriptionAfterReason,
    });
  });
}
