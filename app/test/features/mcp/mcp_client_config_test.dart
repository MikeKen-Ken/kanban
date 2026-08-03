import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/mcp_client_config.dart';
import 'package:kanban/features/mcp/mcp_constants.dart';

void main() {
  group('McpClientConfig.upsertCursorJson', () {
    test('空文件写入 kanbanMCP', () {
      final text = McpClientConfig.upsertCursorJson(null, port: 18765);
      final json = jsonDecode(text) as Map<String, dynamic>;
      final server =
          (json['mcpServers'] as Map)[McpConstants.serverKey] as Map;
      expect(server['url'], McpConstants.endpointUrl(18765));
      expect(server['type'], 'http');
    });

    test('保留已有其他 MCP', () {
      const existing = '''
{
  "mcpServers": {
    "unityMCP": {
      "url": "http://127.0.0.1:8080/mcp"
    }
  }
}
''';
      final text = McpClientConfig.upsertCursorJson(existing, port: 19000);
      final json = jsonDecode(text) as Map<String, dynamic>;
      final servers = json['mcpServers'] as Map;
      expect(servers['unityMCP'], isNotNull);
      expect(
        (servers[McpConstants.serverKey] as Map)['url'],
        McpConstants.endpointUrl(19000),
      );
      expect(McpClientConfig.isCursorConfigured(text, port: 19000), isTrue);
    });
  });

  group('McpClientConfig.upsertCodexToml', () {
    test('空文件写入服务块与 rmcp_client', () {
      final text = McpClientConfig.upsertCodexToml(null, port: 18765);
      expect(text, contains('[mcp_servers.${McpConstants.serverKey}]'));
      expect(text, contains('url = "${McpConstants.endpointUrl(18765)}"'));
      expect(text, contains('[features]'));
      expect(text, contains('rmcp_client = true'));
      expect(McpClientConfig.isCodexConfigured(text, port: 18765), isTrue);
    });

    test('更新已有 kanbanMCP 且保留其他节', () {
      const existing = '''
[mcp_servers.other]
url = "http://127.0.0.1:1/mcp"

[mcp_servers.kanbanMCP]
url = "http://127.0.0.1:1111/mcp"

[features]
rmcp_client = true
''';
      final text = McpClientConfig.upsertCodexToml(existing, port: 18765);
      expect(text, contains('[mcp_servers.other]'));
      expect(text, contains('url = "${McpConstants.endpointUrl(18765)}"'));
      expect(text, isNot(contains('1111')));
      expect(
        RegExp(r'rmcp_client\s*=\s*true').allMatches(text).length,
        1,
      );
    });
  });
}
