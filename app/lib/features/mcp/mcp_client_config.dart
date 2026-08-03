import 'dart:convert';

import 'mcp_constants.dart';

/// Cursor / Codex 配置内容的纯函数 upsert（不碰文件系统，便于单测）。
abstract final class McpClientConfig {
  /// 合并写入 Cursor `mcp.json` 文本。
  static String upsertCursorJson(String? existing, {required int port}) {
    Map<String, dynamic> root;
    if (existing == null || existing.trim().isEmpty) {
      root = {};
    } else {
      final decoded = jsonDecode(existing);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Cursor mcp.json 根节点必须是对象');
      }
      root = Map<String, dynamic>.from(decoded);
    }

    final servers = root['mcpServers'];
    final map = servers is Map
        ? Map<String, dynamic>.from(
            servers.map((key, value) => MapEntry(key.toString(), value)),
          )
        : <String, dynamic>{};

    map[McpConstants.serverKey] = {
      'url': McpConstants.endpointUrl(port),
      'type': 'http',
    };
    root['mcpServers'] = map;
    return const JsonEncoder.withIndent('  ').convert(root);
  }

  /// 合并写入 Codex `config.toml` 文本。
  static String upsertCodexToml(String? existing, {required int port}) {
    final url = McpConstants.endpointUrl(port);
    final source = existing ?? '';
    final withoutServer = _removeTomlTable(
      source,
      'mcp_servers.${McpConstants.serverKey}',
    );
    final withFeatures = _ensureCodexRmcpClient(withoutServer);
    final block = '''
[mcp_servers.${McpConstants.serverKey}]
url = "$url"
''';
    final trimmed = withFeatures.trimRight();
    if (trimmed.isEmpty) return '${block.trimRight()}\n';
    return '$trimmed\n\n${block.trimRight()}\n';
  }

  /// 判断 Cursor JSON 是否已指向当前端点。
  static bool isCursorConfigured(String? existing, {required int port}) {
    if (existing == null || existing.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(existing);
      if (decoded is! Map) return false;
      final servers = decoded['mcpServers'];
      if (servers is! Map) return false;
      final entry = servers[McpConstants.serverKey];
      if (entry is! Map) return false;
      return entry['url'] == McpConstants.endpointUrl(port);
    } catch (_) {
      return false;
    }
  }

  /// 判断 Codex TOML 是否已指向当前端点。
  static bool isCodexConfigured(String? existing, {required int port}) {
    if (existing == null || existing.trim().isEmpty) return false;
    final expected = McpConstants.endpointUrl(port);
    final header = '[mcp_servers.${McpConstants.serverKey}]';
    final start = existing.indexOf(header);
    if (start < 0) return false;
    final rest = existing.substring(start + header.length);
    final nextTable = RegExp(r'^\[', multiLine: true).firstMatch(rest);
    final body = nextTable == null ? rest : rest.substring(0, nextTable.start);
    final match = RegExp(
      r'''url\s*=\s*["']([^"']+)["']''',
    ).firstMatch(body);
    return match?.group(1) == expected;
  }

  static String _ensureCodexRmcpClient(String source) {
    if (RegExp(
      r'^\s*rmcp_client\s*=\s*true\s*$',
      multiLine: true,
    ).hasMatch(source)) {
      return source;
    }

    final featuresHeader = RegExp(r'^\[features\]\s*$', multiLine: true);
    final match = featuresHeader.firstMatch(source);
    if (match == null) {
      final trimmed = source.trimRight();
      final block = '[features]\nrmcp_client = true\n';
      if (trimmed.isEmpty) return block;
      return '$trimmed\n\n$block';
    }

    final insertAt = match.end;
    return '${source.substring(0, insertAt)}\n'
        'rmcp_client = true'
        '${source.substring(insertAt)}';
  }

  static String _removeTomlTable(String source, String tableName) {
    final header = '[$tableName]';
    final start = source.indexOf(header);
    if (start < 0) return source;
    final afterHeader = start + header.length;
    final rest = source.substring(afterHeader);
    final next = RegExp(r'^\[', multiLine: true).firstMatch(rest);
    final end = next == null ? source.length : afterHeader + next.start;
    final before = source.substring(0, start);
    final after = source.substring(end);
    return '$before$after'.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }
}
