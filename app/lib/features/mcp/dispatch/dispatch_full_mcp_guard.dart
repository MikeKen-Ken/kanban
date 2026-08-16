import 'package:mcp_dart/mcp_dart.dart';

import '../mcp_dispatch_card_gate.dart';
import '../mcp_tool_results.dart';

/// 完整 MCP 对锁定卡片的集中写入闸门；应用 UI 不经过这里。
CallToolResult? rejectLockedCardFromFullMcp(
  String cardId, {
  required String operation,
}) {
  final error = McpDispatchCardGate.instance.rejectFullMcpMutation(
    cardId,
    operation: operation,
  );
  return error == null ? null : mcpErrorResult(error);
}
