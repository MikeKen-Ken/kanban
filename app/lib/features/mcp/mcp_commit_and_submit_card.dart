import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_dispatch_card_gate.dart';
import 'mcp_git_commit.dart';
import 'mcp_tool_results.dart';

/// 旧的 Agent 自提交入口。两阶段协议下必须拒绝，改由 Worker finalize。
Future<CallToolResult> mcpCommitAndSubmitCard(
  BoardController controller, {
  required String cardId,
  String? projectId,
  McpGitRunner? gitRunner,
  McpDispatchCardGate? gate,
}) async {
  return mcpErrorResult(
    '调度会话已改为两阶段收尾：Agent 不得自行提交 Git 或送验，请调用 ready_to_submit',
  );
}
