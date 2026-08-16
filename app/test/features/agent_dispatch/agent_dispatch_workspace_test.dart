import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_workspace.dart';

void main() {
  testWidgets('宽窗口并排显示三个工作区', (tester) async {
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

    expect(find.byType(VerticalDivider), findsNWidgets(2));
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

  testWidgets('点击来源图例只显示该类型日志，并隐藏无内容进度行', (tester) async {
    final controller = TextEditingController(
      text: [
        '[09:00:00] [系统] [信息] 系统就绪',
        '[09:00:01] [MCP] [信息] 工具：glob',
        '[09:00:02] [MCP] [信息] 工具：grep {"pattern":"foo"}',
        '[09:00:03] [AI] [信息] 思考中…',
      ].join('\n'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 360,
            child: AgentDispatchLogPane(
              controller: controller,
              running: false,
              onClear: () {},
              onExport: () {},
              onCopy: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('系统就绪'), findsOneWidget);
    expect(find.textContaining('工具：glob'), findsNothing);
    expect(find.textContaining('思考中'), findsNothing);
    expect(find.textContaining('工具：grep'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('agent-dispatch-log-source-mcp')));
    await tester.pump();

    expect(find.textContaining('系统就绪'), findsNothing);
    expect(find.textContaining('工具：grep'), findsOneWidget);
  });

  testWidgets('离开底部后新日志不强制滚到底', (tester) async {
    final controller = TextEditingController(
      text: List.generate(
        80,
        (index) => '[09:00:00] [系统] [信息] line $index',
      ).join('\n'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 240,
            child: AgentDispatchLogPane(
              controller: controller,
              running: false,
              onClear: () {},
              onExport: () {},
              onCopy: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final logScroll = find.byKey(const ValueKey('agent-dispatch-log-scroll'));
    final position = tester.widget<ListView>(logScroll).controller!.position;
    await tester.drag(logScroll, const Offset(0, 180));
    await tester.pumpAndSettle();
    final before = position.pixels;

    controller.text = '${controller.text}\n[09:00:01] [系统] [信息] newest';
    await tester.pump();
    await tester.pump();

    expect(position.pixels, before);
  });

  testWidgets('日志概览突出失败并可按级别筛选', (tester) async {
    final controller = TextEditingController(
      text: [
        '[09:00:00] [MCP] [失败] 提交失败：看板未就绪',
        '[09:00:01] [命令] [警告] 网络连接较慢',
        '[09:00:02] [Worker] [信息] 本会话 token：input=12 output=34 total=46',
      ].join('\n'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 360,
            child: AgentDispatchLogPane(
              controller: controller,
              running: false,
              onClear: () {},
              onExport: () {},
              onCopy: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('失败 '), findsOneWidget);
    expect(find.text('警告 '), findsOneWidget);
    expect(find.text('最新 Token '), findsOneWidget);
    expect(find.text('46'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('agent-dispatch-log-level-error')),
    );
    await tester.pump();

    expect(find.textContaining('提交失败'), findsOneWidget);
    expect(find.textContaining('网络连接较慢'), findsNothing);
    expect(find.textContaining('本会话 token'), findsNothing);
  });
}
