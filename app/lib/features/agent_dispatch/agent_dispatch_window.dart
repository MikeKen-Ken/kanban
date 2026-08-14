import 'package:flutter/material.dart';

import 'agent_dispatch_shell.dart';

/// Agent 工作台窗口：关闭只隐藏，不销毁总览与已打开项目面板的 State。
///
/// Worker 批次由各项目的调度服务持有；隐藏窗口不会停止运行。
class AgentDispatchWindow {
  AgentDispatchWindow._();

  static final ValueNotifier<bool> visible = ValueNotifier(false);
  static final ValueNotifier<String?> selectedProjectId = ValueNotifier(null);
  static final ValueNotifier<List<String>> openedProjectIds =
      ValueNotifier(const []);
  static bool _sessionCreated = false;

  static bool get isVisible => visible.value;

  static bool get hasSession => _sessionCreated;

  static void showHub() {
    _sessionCreated = true;
    selectedProjectId.value = null;
    visible.value = true;
  }

  /// 测试注入面板时只需显示遮罩。
  static void show() => showHub();

  static void openProject(String projectId) {
    final id = projectId.trim();
    if (id.isEmpty) return;
    _sessionCreated = true;
    if (!openedProjectIds.value.contains(id)) {
      openedProjectIds.value = [...openedProjectIds.value, id];
    }
    selectedProjectId.value = id;
    visible.value = true;
  }

  static void backToHub() {
    if (!_sessionCreated) return;
    selectedProjectId.value = null;
    visible.value = true;
  }

  static void hide() {
    visible.value = false;
  }

  /// Esc：项目工作台先回到总览；总览再隐藏窗口。
  static bool hideIfVisible() {
    if (!visible.value) return false;
    if (selectedProjectId.value != null) {
      selectedProjectId.value = null;
      return true;
    }
    hide();
    return true;
  }

  @visibleForTesting
  static void resetForTest() {
    _sessionCreated = false;
    visible.value = false;
    selectedProjectId.value = null;
    openedProjectIds.value = const [];
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
                    onDismiss: () {
                      AgentDispatchWindow.hideIfVisible();
                    },
                    child: panel ?? const AgentDispatchShell(),
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
    // 工作台插在 MaterialApp.builder 中，是根 Navigator Overlay 的兄弟。
    // Overlay：Tooltip / 下拉菜单需要 Overlay 祖先。
    // 内层 Navigator：面板内 showDialog 必须压在工作台之上，不能落到根路由后面。
    // 遮罩不能用「仅一条 DialogRoute」的 barrierDismissible：它是内层 Navigator
    // 的根路由，maybePop 会 bubble，点空白不会关闭。
    return Overlay.wrap(
      clipBehavior: Clip.none,
      child: HeroControllerScope.none(
        child: Navigator(
          onGenerateRoute: (settings) => PageRouteBuilder<void>(
            settings: settings,
            opaque: false,
            pageBuilder: (routeContext, _, __) => Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismiss,
                  child: const ColoredBox(color: Colors.black54),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
