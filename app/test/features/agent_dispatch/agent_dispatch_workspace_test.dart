import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_progress.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_workspace.dart';
import 'package:kanban/features/agent_dispatch/agent_interaction.dart';

void main() {
  testWidgets('宽窗口并排显示三个工作区，Skill 与 Worker 同列', (tester) async {
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
    expect(find.byKey(const ValueKey('agent-dispatch-layout-wide')),
        findsOneWidget);
    expect(find.text('Configuration'), findsOneWidget);
    expect(find.text('批次配置'), findsNothing);
    expect(find.text('对话内容'), findsOneWidget);
  });

  testWidgets('中等窗口保留配置与运行区双列布局', (tester) async {
    tester.view.physicalSize = const Size(1040, 900);
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

    expect(find.byKey(const ValueKey('agent-dispatch-layout-medium')),
        findsOneWidget);
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.text('Configuration'), findsOneWidget);
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

    expect(find.byKey(const ValueKey('agent-dispatch-layout-compact')),
        findsOneWidget);
    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.byType(Divider), findsNWidgets(2));
    expect(find.text('Worker 内容'), findsOneWidget);
    expect(find.text('Skill 内容'), findsOneWidget);
    expect(find.text('批次配置'), findsNothing);
  });

  testWidgets('Skill 预览默认折叠，可展开正文', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 520,
            child: AgentDispatchSkillPane(
              skillPath: '/tmp/skill.md',
              skillPreview: 'Skill 正文预览',
              enabled: true,
              onOpenSkillDirectory: () {},
              onRefreshSkill: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Skill'), findsOneWidget);
    expect(find.text('Skill 正文预览'), findsNothing);
    expect(find.text('/tmp/skill.md'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('agent-dispatch-skill-expand')));
    await tester.pump();

    expect(find.text('Skill 正文预览'), findsOneWidget);
    expect(find.text('/tmp/skill.md'), findsOneWidget);
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
              onExport: (_) {},
              onCopy: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('系统就绪'), findsOneWidget);
    expect(find.textContaining('工具：glob'), findsNothing);
    expect(find.textContaining('思考中'), findsNothing);
    expect(find.textContaining('Tool: grep'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('agent-dispatch-log-source-mcp')));
    await tester.pump();

    expect(find.textContaining('系统就绪'), findsNothing);
    expect(find.textContaining('Tool: grep'), findsOneWidget);
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
              onExport: (_) {},
              onCopy: (_) {},
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
        '[09:00:00] [MCP] [Error] 提交失败：看板未就绪',
        '[09:00:01] [Command] [Warning] 网络连接较慢',
        '[09:00:02] [Worker] [Info] 本会话 token：input=12 output=34 total=46',
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
              onExport: (_) {},
              onCopy: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Error '), findsOneWidget);
    expect(find.text('Warning '), findsOneWidget);
    expect(find.text('Latest token '), findsOneWidget);
    expect(find.text('46'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('agent-dispatch-log-level-error')),
    );
    await tester.pump();

    expect(find.textContaining('提交失败'), findsOneWidget);
    expect(find.textContaining('网络连接较慢'), findsNothing);
    expect(find.textContaining('本会话 token'), findsNothing);
  });

  testWidgets('日志窗口上方显示当前任务进度与实时状态', (tester) async {
    final cardStarted = DateTime.now().subtract(const Duration(seconds: 11));
    final controller = TextEditingController(
      text: [
        '[09:00:00] [Worker] [信息] ──────── Worker 单卡轮次 1/12 ────────',
        '[09:00:01] [系统] [信息] 当前卡片：agent 工作台',
        '[09:00:02] [Worker] [信息] 本卡覆盖：engine=cursor model=composer-2.5 params=[] cardId=x',
        '[09:00:10] [Worker] [信息] Cursor run id=run-1 status=completed steps=3 tools=5 elapsedMs=9000',
        '[09:00:11] [Worker] [信息] 本会话 token：input=12 output=34 total=46',
      ].join('\n'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 420,
            child: AgentDispatchLogPane(
              controller: controller,
              running: true,
              progress: AgentDispatchProgress(
                running: true,
                processedCards: 0,
                totalCards: 12,
                currentRound: 1,
                currentTitle: 'agent 工作台',
                currentDetail: '显示进度与实时状态',
                phaseLabel: '测试',
                cardStartedAt: cardStarted,
              ),
              onClear: () {},
              onExport: (_) {},
              onCopy: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('1/12'), findsOneWidget);
    expect(find.text('测试'), findsOneWidget);
    expect(find.text('agent 工作台'), findsOneWidget);
    expect(find.text('显示进度与实时状态'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-dispatch-card-metrics')),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-dispatch-card-token')),
        matching: find.text('46'),
      ),
      findsOneWidget,
    );
    expect(find.text('9s'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-dispatch-card-elapsed')),
        matching: find.textContaining(RegExp(r'^\d+s$')),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Steps 3'), findsOneWidget);
    expect(find.textContaining('cursor'), findsOneWidget);
  });

  testWidgets('可按第几个任务筛选日志，复制只包含该任务', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController(
      text: [
        '[09:00:00] [系统] [信息] 启动批次',
        '[09:00:01] [Worker] [信息] ──────── Worker 单卡轮次 1/2 ────────',
        '[09:00:02] [系统] [信息] 当前卡片：任务甲',
        '[09:00:03] [AI] [信息] 助手：完成甲',
        '[09:00:04] [Worker] [信息] ──────── Worker 单卡轮次 2/2 ────────',
        '[09:00:05] [系统] [信息] 当前卡片：任务乙',
        '[09:00:06] [AI] [信息] 助手：完成乙',
      ].join('\n'),
    );
    addTearDown(controller.dispose);
    String? copied;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 900,
            child: AgentDispatchLogPane(
              controller: controller,
              running: false,
              onClear: () {},
              onExport: (_) {},
              onCopy: (log) => copied = log,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('完成甲'), findsOneWidget);
    expect(find.textContaining('完成乙', skipOffstage: false), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('agent-dispatch-log-task-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-dispatch-log-task-2')));
    await tester.pumpAndSettle();

    expect(find.textContaining('完成甲', skipOffstage: false), findsNothing);
    expect(find.textContaining('完成乙', skipOffstage: false), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-dispatch-log-copy')));
    await tester.pump();

    expect(copied, contains('完成乙'));
    expect(copied, isNot(contains('完成甲')));
    expect(copied, isNot(contains('启动批次')));

    await tester
        .tap(find.byKey(const ValueKey('agent-dispatch-log-task-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-dispatch-log-task-all')));
    await tester.pumpAndSettle();

    expect(find.textContaining('完成甲'), findsOneWidget);
    expect(find.textContaining('完成乙', skipOffstage: false), findsOneWidget);
    expect(find.text('All tasks'), findsOneWidget);
  });

  testWidgets('切换任务后状态区跟随该卡，并可跳回运行中卡片', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController(
      text: [
        '[09:00:01] [Worker] [信息] ──────── Worker 单卡轮次 1/2 ────────',
        '[09:00:02] [系统] [信息] 当前卡片：任务甲',
        '[09:00:03] [系统] [信息] 当前任务：已完成的需求',
        '[09:00:04] [AI] [信息] 助手：完成甲',
        '[09:00:05] [Worker] [信息] ──────── Worker 单卡轮次 2/2 ────────',
        '[09:00:06] [系统] [信息] 当前卡片：任务乙',
        '[09:00:07] [系统] [信息] 当前任务：正在实施',
        '[09:00:08] [AI] [信息] 助手：处理乙',
      ].join('\n'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 900,
            child: AgentDispatchLogPane(
              controller: controller,
              running: true,
              progress: const AgentDispatchProgress(
                running: true,
                currentRound: 2,
                totalCards: 2,
                currentTitle: '任务乙',
                currentDetail: '正在实施',
                phaseLabel: '实施',
              ),
              onClear: () {},
              onExport: (_) {},
              onCopy: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('agent-dispatch-task-title')))
          .data,
      '任务乙',
    );
    expect(find.byKey(const ValueKey('agent-dispatch-jump-running-card')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('agent-dispatch-log-task-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-dispatch-log-task-1')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('agent-dispatch-task-title')))
          .data,
      '任务甲',
    );
    expect(find.text('已完成的需求'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-dispatch-jump-running-card')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('agent-dispatch-jump-running-card')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('agent-dispatch-task-title')))
          .data,
      '任务乙',
    );
    expect(find.textContaining('处理乙', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('完成甲', skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('agent-dispatch-jump-running-card')),
        findsNothing);
  });

  testWidgets('最近运行在提问时弹出选项菜单并可点选', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController(text: '[09:00:00] [系统] [信息] 运行中');
    addTearDown(controller.dispose);
    var replied = '';
    final pending = AgentInteractionEvent(
      type: AgentInteractionEventType.question,
      cardId: 'card-a',
      sessionId: 'session-a',
      text: '请选择方案',
      at: DateTime.utc(2026, 8, 20),
      requestId: 'request-a',
      choices: const ['方案 A', '方案 B', '方案 C'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 900,
            child: AgentDispatchLogPane(
              controller: controller,
              running: true,
              pendingInteraction: pending,
              onInteractionReply: (text) async {
                replied = text;
                return true;
              },
              onClear: () {},
              onExport: (_) {},
              onCopy: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('agent-dispatch-interaction-prompt')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-dispatch-interaction-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('agent-dispatch-interaction-dialog-choice-1')),
    );
    await tester.pump();
    expect(replied, '方案 B');
  });

  testWidgets('问题正文编号列表也会弹出选项菜单', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController(text: '[09:00:00] [系统] [信息] 运行中');
    addTearDown(controller.dispose);
    final pending = parseAgentInteractionEvent(
      '@@KANBAN_INTERACTION@@'
      '{"type":"question","cardId":"card-a","sessionId":"session-a",'
      '"requestId":"request-a","text":"请选择方案\\n1. 方案 A\\n2. 方案 B\\n3. 方案 C",'
      '"at":"2026-08-20T08:00:00Z"}',
    )!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 900,
            child: AgentDispatchLogPane(
              controller: controller,
              running: true,
              pendingInteraction: pending,
              onInteractionReply: (text) async => true,
              onClear: () {},
              onExport: (_) {},
              onCopy: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('agent-dispatch-interaction-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-dispatch-interaction-dialog-choice-2')),
      findsOneWidget,
    );
  });
}
