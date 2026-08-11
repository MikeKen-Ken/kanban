import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

/// 写入或清除卡片上的 Git 提交号。
Future<CallToolResult> mcpSetCardCommitRef(
  BoardController controller, {
  required String cardId,
  String? projectId,
  String? commitRef,
  bool clearCommitRef = false,
}) async {
  final located = await resolveMcpProjectIdForCard(
    controller,
    cardId: cardId,
    projectId: projectId,
  );
  if (located.error != null) return located.error!;

  final columnId = located.columnId;
  if (columnId == null) {
    return mcpErrorResult('未找到卡片所在列：$cardId');
  }

  final normalized = mcpTrimmedString(commitRef);
  final shouldClear = clearCommitRef || (normalized?.isEmpty ?? false);
  if (!shouldClear && normalized == null) {
    return mcpErrorResult('commitRef 不能为空（或传 clearCommitRef=true 清除）');
  }

  return runMcpForProject(controller, located.projectId!, (resolvedProjectId) async {
    final updateError = await controller.updateCardFull(
      columnId,
      cardId,
      commitRef: shouldClear ? null : normalized,
      clearCommitRef: shouldClear,
    );
    if (updateError != null) return mcpErrorResult(updateError);

    final actualColumnId =
        controller.findColumnIdForCard(cardId) ?? columnId;
    return mcpJsonResult({
      'ok': true,
      'cardId': cardId,
      'columnId': actualColumnId,
      'projectId': resolvedProjectId,
      'commitRef': shouldClear ? null : normalized,
    });
  });
}
