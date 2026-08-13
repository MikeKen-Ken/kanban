import 'package:flutter/material.dart';

import 'agent_dispatch_panel.dart';
import 'agent_dispatch_platform.dart';
import 'agent_dispatch_service.dart';

/// Agent 工作台窗口：关闭只隐藏，不销毁面板 State。
///
/// Worker 批次由 [AgentDispatchService] 持有；隐藏窗口不会停止运行，
/// 再次打开时配置、日志与「运行中」状态都还在。
class AgentDispatchWindow {
  AgentDispatchWindow._();

  static final ValueNotifier<bool> visible = ValueNotifier(false);
  static bool _sessionCreated = false;

  static bool get isVisible => visible.value;

  static bool get hasSession => _sessionCreated;

  static void show() {
    _sessionCreated = true;
    visible.value = true;
  }

  static void hide() {
    visible.value = false;
  }

  /// 若工作台正显示则隐藏并返回 true，供 Esc 优先处理。
  static bool hideIfVisible() {
    if (!visible.value) return false;
    hide();
    return true;
  }

  @visibleForTesting
  static void resetForTest() {
    _sessionCreated = false;
    visible.value = false;
  }
}

/// 插在 [MaterialApp.builder] 中：首次打开后用 Offstage 保活面板。
class AgentDispatchWindowHost extends StatelessWidget {
  const AgentDispatchWindowHost({
    required this.child,
    this.panel,
    super.key,
  });

  final Widget child;

  /// 测试可注入占位面板，避免拉起完整调度 UI。
  final Widget? panel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AgentDispatchWindow.visible,
      child: child,
      builder: (context, visible, appChild) {
        return Stack(
          fit: StackFit.expand,
          children: [
            appChild ?? const SizedBox.shrink(),
            if (AgentDispatchWindow.hasSession)
              ExcludeFocus(
                excluding: !visible,
                child: Offstage(
                  offstage: !visible,
                  child: _AgentDispatchScrim(
                    onDismiss: AgentDispatchWindow.hide,
                    child: panel ?? const AgentDispatchPanel(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AgentDispatchScrim extends StatelessWidget {
  const _AgentDispatchScrim({
    required this.onDismiss,
    required this.child,
  });

  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 工作台插在 MaterialApp.builder 中，是 Navigator Overlay 的兄弟而不是后代。
    // Tooltip / 下拉菜单 / PopupMenu 都需要 Overlay 祖先，否则悬停会插入失败，
    // 在 Release 里表现为一块巨大的空灰色 ErrorWidget。
    return Overlay.wrap(
      clipBehavior: Clip.none,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ModalBarrier(
            dismissible: true,
            color: Colors.black54,
            onDismiss: onDismiss,
          ),
          SafeArea(
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}

void showAgentDispatchPanel(BuildContext context) {
  AgentDispatchWindow.show();
}

/// 左上角「新建项目」右侧入口（仅桌面）。
class AgentDispatchToolbarButton extends StatefulWidget {
  const AgentDispatchToolbarButton({super.key});

  @override
  State<AgentDispatchToolbarButton> createState() =>
      _AgentDispatchToolbarButtonState();
}

class _AgentDispatchToolbarButtonState extends State<AgentDispatchToolbarButton> {
  final _service = AgentDispatchService();

  @override
  void initState() {
    super.initState();
    _service.addRunningListener(_onRunningChanged);
  }

  @override
  void dispose() {
    _service.removeRunningListener(_onRunningChanged);
    super.dispose();
  }

  void _onRunningChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!isAgentDispatchDesktop) return const SizedBox.shrink();
    final running = _service.isRunning;
    return IconButton(
      tooltip: running ? 'Agent 调度（运行中）' : 'Agent 调度',
      icon: Icon(running ? Icons.smart_toy : Icons.smart_toy_outlined),
      onPressed: () => showAgentDispatchPanel(context),
    );
  }
}
