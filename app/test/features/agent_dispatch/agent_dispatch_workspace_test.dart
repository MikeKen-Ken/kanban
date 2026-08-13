import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_workspace.dart';

void main() {
  testWidgets('宽窗口并排显示四个工作区', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentDispatchWorkspace(
            worker: Text('Worker 内容'),
            skill: Text('Skill 内容'),
            settings: Text('设置内容'),
            log: Text('对话内容'),
          ),
        ),
      ),
    );

    expect(find.byType(VerticalDivider), findsNWidgets(3));
    expect(find.text('Worker 内容'), findsOneWidget);
    expect(find.text('Skill 内容'), findsOneWidget);
    expect(find.text('调度配置'), findsOneWidget);
    expect(find.text('对话内容'), findsOneWidget);
  });

  testWidgets('窄窗口回退为纵向排列', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentDispatchWorkspace(
            worker: Text('Worker 内容'),
            skill: Text('Skill 内容'),
            settings: Text('设置内容'),
            log: Text('对话内容'),
          ),
        ),
      ),
    );

    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.byType(Divider), findsNWidgets(3));
  });
}
