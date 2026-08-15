import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_constants.dart';
import 'mcp_paths.dart';
import 'mcp_tools.dart';

enum KanbanMcpStatus { stopped, starting, running, error }

/// Windows 上托管 Streamable HTTP MCP；其它平台为空操作。
class KanbanMcpHost extends ChangeNotifier {
  KanbanMcpHost(this._controller);

  final BoardController _controller;
  StreamableMcpServer? _server;
  StreamableMcpServer? _agentServer;
  KanbanMcpStatus status = KanbanMcpStatus.stopped;
  String? lastError;
  int boundPort = McpConstants.defaultPort;
  int agentBoundPort = McpConstants.defaultPort;

  bool get isSupported => McpPaths.isWindowsSupported;

  String get endpointUrl => McpConstants.endpointUrl(boundPort);

  /// Skill 会话专用端点（与完整目录同 path、不同端口）。未启动时为 null，禁止回退。
  String? get agentEndpointUrl =>
      _agentServer == null
          ? null
          : McpConstants.agentEndpointUrl(agentBoundPort);

  bool get hasAgentSessionServer => _agentServer != null;

  bool get isRunning => status == KanbanMcpStatus.running;

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
      await _startAgentServer();
      status = KanbanMcpStatus.running;
      debugPrint('看板 MCP 已监听 $endpointUrl');
      debugPrint('调度 Skill MCP 已监听 $agentEndpointUrl');
    } catch (error) {
      await _closeServers();
      status = KanbanMcpStatus.error;
      lastError ??= error.toString();
      debugPrint('看板 MCP 启动失败：$lastError');
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
    final agentServer = _agentServer;
    _agentServer = null;
    if (agentServer != null) {
      try {
        await agentServer.stop();
      } catch (error) {
        debugPrint('调度 Skill MCP 停止失败：$error');
      }
    }
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.stop();
      } catch (error) {
        debugPrint('看板 MCP 停止失败：$error');
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
    registerKanbanMcpTools(server, _controller);
    return server;
  }

  Future<void> _startAgentServer() async {
    try {
      final server = StreamableMcpServer(
        serverFactory: (_) => _buildAgentServer(),
        host: McpConstants.host,
        port: 0,
        path: McpConstants.path,
        eventStore: InMemoryEventStore(),
        enableDnsRebindingProtection: true,
        allowedHosts: const {'127.0.0.1', 'localhost'},
        enableJsonResponse: true,
      );
      await server.start();
      _agentServer = server;
      agentBoundPort = server.boundPort;
    } catch (error) {
      _agentServer = null;
      lastError = '调度 Skill MCP 启动失败：$error';
      debugPrint(lastError);
      rethrow;
    }
  }

  McpServer _buildAgentServer() {
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
      toolset: KanbanMcpToolset.agentSession,
    );
    return server;
  }

  @override
  void dispose() {
    final agentServer = _agentServer;
    _agentServer = null;
    agentServer?.stop();
    final server = _server;
    _server = null;
    server?.stop();
    super.dispose();
  }
}
