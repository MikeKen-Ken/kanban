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
    // 工作台插在 MaterialApp.builder 中，是 Navigator Overlay 的兄弟而不是后代。
    // Tooltip / 下拉菜单 / PopupMenu 都需要 Overlay 祖先，否则悬停会插入失败，
    // 在 Release 里表现为一块巨大的空灰色 ErrorWidget。
    // 用 DialogRoute 自带遮罩：空白处可点，对话框本身不拦截全屏命中。
    return Overlay.wrap(
      clipBehavior: Clip.none,
      child: HeroControllerScope.none(
        child: Navigator(
          onGenerateRoute: (settings) => DialogRoute<void>(
            context: context,
            barrierDismissible: true,
            barrierColor: Colors.black54,
            settings: settings,
            builder: (routeContext) => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) onDismiss();
              },
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
