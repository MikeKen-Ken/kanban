import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';
import 'mcp_work_scope_result.dart';

/// 按需拉取本轮工作范围；附件内容一并内联。
Future<CallToolResult> mcpGetWorkItems(
  BoardController controller, {
  required String cardId,
  String? projectId,
}) async {
  final located = await resolveMcpProjectIdForCard(
    controller,
    cardId: cardId,
    projectId: projectId,
  );
  if (located.error != null) return located.error!;

  return runMcpForProject(controller, located.projectId, (resolvedProjectId) async {
    final card = controller.findCardById(cardId);
    if (card == null) return mcpErrorResult('未找到卡片：$cardId');

    return mcpWorkScopeResult(
      controller: controller,
      projectId: resolvedProjectId,
      card: card,
      basePayload: {
        'projectId': resolvedProjectId,
        'cardId': cardId,
      },
    );
  });
}
