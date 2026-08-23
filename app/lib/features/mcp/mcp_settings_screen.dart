import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../settings/settings_section.dart';
import 'kanban_mcp_host.dart';
import 'mcp_client_configurator.dart';
import 'mcp_constants.dart';
import 'mcp_paths.dart';
import '../../common/app_snack_bar.dart';

/// Windows MCP 服务状态与 Cursor / Codex 一键配置。
class McpSettingsScreen extends StatefulWidget {
  const McpSettingsScreen({super.key});

  @override
  State<McpSettingsScreen> createState() => _McpSettingsScreenState();
}

class _McpSettingsScreenState extends State<McpSettingsScreen> {
  late final TextEditingController _portController;
  late final KanbanMcpHost _host;
  bool? _cursorConfigured;
  bool? _codexConfigured;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<BoardController>();
    _host = controller.mcpHost;
    _portController =
        TextEditingController(text: '${controller.appSettings.mcpPort}');
    _host.addListener(_onHostChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshClientStatus());
  }

  @override
  void dispose() {
    _host.removeListener(_onHostChanged);
    _portController.dispose();
    super.dispose();
  }

  void _onHostChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshClientStatus() async {
    final port = context.read<BoardController>().appSettings.mcpPort;
    final cursor = await McpClientConfigurator.isConfigured(
      McpClientKind.cursor,
      port: port,
    );
    final codex = await McpClientConfigurator.isConfigured(
      McpClientKind.codex,
      port: port,
    );
    if (!mounted) return;
    setState(() {
      _cursorConfigured = cursor;
      _codexConfigured = codex;
    });
  }

  Future<void> _setEnabled(bool enabled) async {
    final controller = context.read<BoardController>();
    await controller.saveAppSettings(
      controller.appSettings.copyWith(mcpEnabled: enabled),
    );
  }

  Future<void> _applyPort() async {
    final parsed = int.tryParse(_portController.text.trim());
    if (parsed == null || parsed < 1 || parsed > 65535) {
      _snack('Port must be between 1 and 65535');
      return;
    }
    final controller = context.read<BoardController>();
    await controller.saveAppSettings(
      controller.appSettings.copyWith(mcpPort: parsed),
    );
    await _refreshClientStatus();
    _snack('Port updated');
  }

  Future<void> _configure(McpClientKind kind) async {
    setState(() => _busy = true);
    final port = context.read<BoardController>().appSettings.mcpPort;
    final result = await McpClientConfigurator.configure(kind, port: port);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(result.message);
    await _refreshClientStatus();
  }

  Future<void> _configureAll() async {
    setState(() => _busy = true);
    final port = context.read<BoardController>().appSettings.mcpPort;
    final cursor = await McpClientConfigurator.configure(
      McpClientKind.cursor,
      port: port,
    );
    final codex = await McpClientConfigurator.configure(
      McpClientKind.codex,
      port: port,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _snack('${cursor.message}; ${codex.message}');
    await _refreshClientStatus();
  }

  void _snack(String message) {
    showAppSnackBar(context, message: message);
  }

  String _statusLabel(KanbanMcpHost host) {
    if (!host.isSupported) return 'Available on Windows only';
    return switch (host.status) {
      KanbanMcpStatus.stopped => 'Stopped',
      KanbanMcpStatus.starting => 'Starting…',
      KanbanMcpStatus.running => 'Running',
      KanbanMcpStatus.error => 'Failed to start',
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BoardController>();
    final host = controller.mcpHost;
    final settings = controller.appSettings;
    final supported = McpPaths.isWindowsSupported;

    return Scaffold(
      appBar: AppBar(title: const Text('MCP / AI control')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SettingsSection(
            icon: Icons.hub_outlined,
            title: 'Local MCP service',
            subtitle:
                'Windows only; not synced. Default: ${McpConstants.endpointUrl()}',
            children: [
              SwitchListTile(
                title: const Text('Enable MCP'),
                subtitle: Text(_statusLabel(host)),
                value: settings.mcpEnabled && supported,
                onChanged:
                    !supported || _busy ? null : (value) => _setEnabled(value),
              ),
              ListTile(
                title: const Text('Endpoint'),
                subtitle: Text(host.endpointUrl),
                trailing: IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: host.endpointUrl),
                    );
                    if (!context.mounted) return;
                    _snack('Endpoint copied');
                  },
                ),
              ),
              if (host.lastError != null &&
                  host.status == KanbanMcpStatus.error)
                ListTile(
                  leading: Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(host.lastError!),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _portController,
                        enabled: supported && !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: supported && !_busy ? _applyPort : null,
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            icon: Icons.psychology_outlined,
            title: 'One-click client setup',
            subtitle:
                'Writes to local Cursor / Codex global configuration without overwriting other MCP servers',
            children: [
              SettingsNavigationTile(
                icon: Icons.flash_on_outlined,
                title: 'Set up all',
                subtitle: 'Configure both Cursor and Codex',
                onTap: () {
                  if (!supported || _busy) return;
                  _configureAll();
                },
              ),
              const Divider(),
              SettingsNavigationTile(
                icon: Icons.code_outlined,
                title: 'Set up Cursor',
                subtitle: _clientSubtitle(
                  configured: _cursorConfigured,
                  path: McpPaths.cursorMcpJsonPath,
                ),
                onTap: () {
                  if (!supported || _busy) return;
                  _configure(McpClientKind.cursor);
                },
              ),
              SettingsNavigationTile(
                icon: Icons.terminal_outlined,
                title: 'Set up Codex',
                subtitle: _clientSubtitle(
                  configured: _codexConfigured,
                  path: McpPaths.codexConfigTomlPath,
                ),
                onTap: () {
                  if (!supported || _busy) return;
                  _configure(McpClientKind.codex);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SettingsSection(
            icon: Icons.info_outline,
            title: 'How to use it',
            subtitle: 'Service name: kanbanMCP',
            children: [
              ListTile(
                title: Text('1. Open this app and enable MCP'),
                subtitle: Text(
                    'The service listens on 127.0.0.1 and is available locally only'),
              ),
              ListTile(
                title: Text('2. Set up Cursor or Codex'),
                subtitle:
                    Text('Restart the chosen client, then enable kanbanMCP'),
              ),
              ListTile(
                title: Text('3. Use AI to read and update tasks'),
                subtitle: Text(
                  'Use tools such as list_projects, search_cards, '
                  'create_card, move_card, and complete_card',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _clientSubtitle({required bool? configured, required String? path}) {
    final status = switch (configured) {
      true => 'Configured',
      false => 'Not configured',
      null => 'Checking…',
    };
    if (path == null || path.isEmpty) return status;
    return '$status · $path';
  }
}
