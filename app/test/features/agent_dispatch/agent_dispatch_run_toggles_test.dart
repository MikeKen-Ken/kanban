import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_run_toggles.dart';

void main() {
  testWidgets('运行开关只显示标题、不带解释文案', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentDispatchRunToggles(
            ignoreCardParams: false,
            allowDirtyWorkspace: false,
            enableSandbox: false,
            requireTests: false,
            terminateAfterDispatchTerminal: true,
            enabled: true,
            onIgnoreCardParamsChanged: _noop,
            onAllowDirtyWorkspaceChanged: _noop,
            onEnableSandboxChanged: _noop,
            onRequireTestsChanged: _noop,
            onTerminateAfterDispatchTerminalChanged: _noop,
          ),
        ),
      ),
    );

    expect(find.text('允许使用卡片参数'), findsOneWidget);
    expect(find.text('允许脏工作区'), findsOneWidget);
    expect(find.text('开沙箱'), findsOneWidget);
    expect(find.text('需要测试'), findsOneWidget);
    expect(find.text('收尾后主动结束会话'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(5));
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(ToggleButtons), findsNothing);
    expect(find.textContaining('打开后忽略卡片'), findsNothing);
    expect(find.textContaining('未提交改动'), findsNothing);
  });

  testWidgets('勾选允许使用卡片参数时关闭 ignoreCardParams', (tester) async {
    var ignoreCardParams = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AgentDispatchRunToggles(
                ignoreCardParams: ignoreCardParams,
                allowDirtyWorkspace: false,
                enableSandbox: false,
                requireTests: false,
                terminateAfterDispatchTerminal: true,
                enabled: true,
                onIgnoreCardParamsChanged: (value) {
                  setState(() => ignoreCardParams = value);
                },
                onAllowDirtyWorkspaceChanged: _noop,
                onEnableSandboxChanged: _noop,
                onRequireTestsChanged: _noop,
                onTerminateAfterDispatchTerminalChanged: _noop,
              );
            },
          ),
        ),
      ),
    );

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox).first);
    expect(checkbox.value, isFalse);

    await tester.tap(find.text('允许使用卡片参数'));
    await tester.pump();

    expect(ignoreCardParams, isFalse);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
  });
}

void _noop(bool _) {}
