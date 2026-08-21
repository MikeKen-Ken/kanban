import 'package:flutter/material.dart';

import 'agent_dispatch_platform.dart';
import 'agent_dispatch_registry.dart';
import 'agent_dispatch_window.dart';

/// 左上角「新建项目」右侧入口（仅桌面）。
class AgentDispatchToolbarButton extends StatefulWidget {
  const AgentDispatchToolbarButton({super.key});

  @override
  State<AgentDispatchToolbarButton> createState() =>
      _AgentDispatchToolbarButtonState();
}

class _AgentDispatchToolbarButtonState
    extends State<AgentDispatchToolbarButton> {
  final _registry = AgentDispatchRegistry.instance;

  @override
  void initState() {
    super.initState();
    _registry.addListener(_onChanged);
  }

  @override
  void dispose() {
    _registry.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!isAgentDispatchDesktop) return const SizedBox.shrink();
    final runningCount = _registry.runningCount;
    final tooltip = runningCount > 0
        ? 'Agent Dispatch ($runningCount project(s) running)'
        : 'Agent Dispatch';
    return IconButton(
      tooltip: tooltip,
      icon: Icon(
        runningCount > 0 ? Icons.smart_toy : Icons.smart_toy_outlined,
      ),
      onPressed: AgentDispatchWindow.showHub,
    );
  }
}
