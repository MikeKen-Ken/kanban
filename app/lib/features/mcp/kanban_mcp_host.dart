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
  KanbanMcpStatus status = KanbanMcpStatus.stopped;
  String? lastError;
  int boundPort = McpConstants.defaultPort;

  bool get isSupported => McpPaths.isWindowsSupported;

  String get endpointUrl => McpConstants.endpointUrl(boundPort);

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
      status = KanbanMcpStatus.running;
      debugPrint('看板 MCP 已监听 $endpointUrl');
    } catch (error) {
      _server = null;
      status = KanbanMcpStatus.error;
      lastError = error.toString();
      debugPrint('看板 MCP 启动失败：$error');
    }
    notifyListeners();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.stop();
      } catch (error) {
        debugPrint('看板 MCP 停止失败：$error');
      }
    }
    if (status != KanbanMcpStatus.stopped || lastError != null) {
      status = KanbanMcpStatus.stopped;
      // 保留 lastError 供「曾失败」查看；主动 stop 时清空
      if (lastError != null && !isSupported) {
        // no-op
      }
      notifyListeners();
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

  @override
  void dispose() {
    // 异步 stop；dispose 路径尽力关闭
    final server = _server;
    _server = null;
    server?.stop();
    super.dispose();
  }
}
