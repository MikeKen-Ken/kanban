import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

/// 将对象序列化为 MCP 文本结果。
CallToolResult mcpJsonResult(Object data) {
  return CallToolResult(
    content: [
      TextContent(text: jsonEncode(data)),
    ],
  );
}

/// 返回带 isError 标记的 MCP 文本错误。
CallToolResult mcpErrorResult(String message) {
  return CallToolResult(
    isError: true,
    content: [TextContent(text: message)],
  );
}
