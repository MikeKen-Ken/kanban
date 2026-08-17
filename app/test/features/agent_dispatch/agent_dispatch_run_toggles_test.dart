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
            enabled: true,
            onIgnoreCardParamsChanged: _noop,
            onAllowDirtyWorkspaceChanged: _noop,
          ),
        ),
      ),
    );

    expect(find.text('禁止使用卡片参数'), findsOneWidget);
    expect(find.text('允许脏工作区'), findsOneWidget);
    expect(find.textContaining('打开后忽略卡片'), findsNothing);
    expect(find.textContaining('未提交改动'), findsNothing);
  });
}

void _noop(bool _) {}
