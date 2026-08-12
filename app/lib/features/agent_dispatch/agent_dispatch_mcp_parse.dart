import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

/// 从 MCP [CallToolResult] 取出首段文本。
String? mcpCallToolText(CallToolResult result) {
  for (final block in result.content) {
    if (block is TextContent) return block.text;
  }
  return null;
}

/// 解析 MCP JSON 文本结果；失败返回 null。
Map<String, dynamic>? mcpCallToolJson(CallToolResult result) {
  final text = mcpCallToolText(result);
  if (text == null || text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } catch (_) {
    return null;
  }
}
