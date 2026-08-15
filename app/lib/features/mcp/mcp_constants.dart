/// Windows 内嵌 MCP 的固定约定。
abstract final class McpConstants {
  /// 客户端配置中的服务名（与 unityMCP 并列，互不覆盖）。
  static const serverKey = 'kanbanMCP';

  /// 默认监听端口（避开 Unity MCP 常用的 8080）。
  static const defaultPort = 18765;

  static const host = '127.0.0.1';
  static const path = '/mcp';

  static const implementationName = 'kanban-mcp';
  static const implementationVersion = '1.0.0';

  static String endpointUrl([int port = defaultPort]) =>
      'http://$host:$port$path';

  /// Skill 会话专用端点，只暴露取卡/咨询/提交/阻塞。
  static String agentEndpointUrl(int port) =>
      'http://$host:$port$path';
}
