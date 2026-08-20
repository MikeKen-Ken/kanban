import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_tools_agent_session.dart';
import 'mcp_constants.dart';
import 'mcp_paths.dart';
import 'mcp_tools.dart';

enum KanbanMcpStatus { stopped, starting, running, error }

/// Windows 上托管 Streamable HTTP MCP；其它平台为空操作。
class KanbanMcpHost extends ChangeNotifier {
  KanbanMcpHost(this._controller);

  final BoardController _controller;
  StreamableMcpServer? _server;
  final _scopedServersByToken = <String, StreamableMcpServer>{};
  KanbanMcpStatus status = KanbanMcpStatus.stopped;
  String? lastError;
  int boundPort = McpConstants.defaultPort;

  bool get isSupported => McpPaths.isWindowsSupported;

  String get endpointUrl => McpConstants.endpointUrl(boundPort);

  /// 兼容旧 UI；Agent 端点现由每次 claim 的结果返回。
  String? get agentEndpointUrl => null;

  bool get hasAgentSessionServer => _scopedServersByToken.isNotEmpty;

  bool get isRunning => status == KanbanMcpStatus.running;

  /// App 调度 finally 使用；即使 Worker 未能调用私有 close，也会按 token 回收端点。
  Future<void> closeScopedEndpoint(String workerToken) =>
      _closeScopedAgentServer(workerToken);

  /// 按本机偏好启停服务。
  Future<void> syncWithSettings({
    required bool enabled,
    required int port,
  }) async {
    if (!isSupported) {
      await stop();
      return;
    }
    if (!enabled) {
      await stop();
      return;
    }
    if (isRunning && boundPort == port) return;
    await start(port: port);
  }

  Future<void> start({int port = McpConstants.defaultPort}) async {
    if (!isSupported) {
      lastError = '当前平台不支持内嵌 MCP';
      status = KanbanMcpStatus.error;
      notifyListeners();
      return;
    }

    await stop();
    status = KanbanMcpStatus.starting;
    lastError = null;
    boundPort = port;
    notifyListeners();

    try {
      final server = StreamableMcpServer(
        serverFactory: (_) => _buildServer(),
        host: McpConstants.host,
        port: port,
        path: McpConstants.path,
        eventStore: InMemoryEventStore(),
        enableDnsRebindingProtection: true,
        allowedHosts: const {'127.0.0.1', 'localhost'},
        // 本机 AI 客户端可能不带 Origin；不强制 Origin 白名单
        enableJsonResponse: true,
      );
      await server.start();
      _server = server;
      boundPort = server.boundPort;
      status = KanbanMcpStatus.running;
      debugPrint('Kanban MCP listening at $endpointUrl');
    } catch (error) {
      await _closeServers();
      status = KanbanMcpStatus.error;
      lastError ??= error.toString();
      debugPrint('Kanban MCP failed to start: $lastError');
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _closeServers();
    if (status != KanbanMcpStatus.stopped || lastError != null) {
      status = KanbanMcpStatus.stopped;
      notifyListeners();
    }
  }

  Future<void> _closeServers() async {
    final scopedServers = _scopedServersByToken.values.toList();
    _scopedServersByToken.clear();
    for (final scopedServer in scopedServers) {
      try {
        await scopedServer.stop();
      } catch (error) {
        debugPrint('Failed to stop scoped MCP dispatcher: $error');
      }
    }
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.stop();
      } catch (error) {
        debugPrint('Failed to stop Kanban MCP: $error');
      }
    }
  }

  McpServer _buildServer() {
    final server = McpServer(
      const Implementation(
        name: McpConstants.implementationName,
        version: McpConstants.implementationVersion,
      ),
      options: const McpServerOptions(
        protocol: McpProtocol.stable,
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(),
        ),
      ),
    );
    registerKanbanMcpTools(
      server,
      _controller,
      startScopedEndpoint: _startScopedAgentServer,
      closeScopedEndpoint: _closeScopedAgentServer,
    );
    return server;
  }

  Future<String> _startScopedAgentServer({
    required String workerToken,
    required String cardId,
  }) async {
    await _closeScopedAgentServer(workerToken);
    try {
      final server = StreamableMcpServer(
        serverFactory: (_) => _buildAgentServer(
          workerToken: workerToken,
          cardId: cardId,
        ),
        host: McpConstants.host,
        port: 0,
        path: McpConstants.path,
        eventStore: InMemoryEventStore(),
        enableDnsRebindingProtection: true,
        allowedHosts: const {'127.0.0.1', 'localhost'},
        enableJsonResponse: true,
      );
      await server.start();
      _scopedServersByToken[workerToken] = server;
      final endpoint = McpConstants.agentEndpointUrl(server.boundPort);
      debugPrint('Scoped MCP dispatcher listening at $endpoint');
      return endpoint;
    } catch (error) {
      lastError = '调度 scoped MCP 启动失败：$error';
      debugPrint(lastError!);
      rethrow;
    }
  }

  Future<void> _closeScopedAgentServer(String workerToken) async {
    final server = _scopedServersByToken.remove(workerToken);
    if (server == null) return;
    try {
      await server.stop();
    } catch (error) {
      debugPrint('Failed to stop scoped MCP dispatcher: $error');
    }
  }

  McpServer _buildAgentServer({
    required String workerToken,
    required String cardId,
  }) {
    final server = McpServer(
      const Implementation(
        name: McpConstants.implementationName,
        version: McpConstants.implementationVersion,
      ),
      options: const McpServerOptions(
        protocol: McpProtocol.stable,
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(),
        ),
      ),
    );
    registerKanbanMcpAgentSessionTools(
      server,
      _controller,
      workerToken: workerToken,
      cardId: cardId,
    );
    return server;
  }

  @override
  void dispose() {
    for (final server in _scopedServersByToken.values) {
      server.stop();
    }
    _scopedServersByToken.clear();
    final server = _server;
    _server = null;
    server?.stop();
    super.dispose();
  }
}
