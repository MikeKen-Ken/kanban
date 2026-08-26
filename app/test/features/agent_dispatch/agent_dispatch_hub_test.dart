import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_hub.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_hub_overview.dart';
import 'package:kanban/features/project/project_list_preferences.dart';
import 'package:kanban/features/project/projects_manifest.dart';

void main() {
  test('运行中项目置顶，但保留原项目顺序', () {
    final ordered = orderAgentDispatchHubItems(const [
      AgentDispatchHubItem(projectId: 'b', title: '项目乙', running: false),
      AgentDispatchHubItem(projectId: 'a', title: '项目甲', running: true),
      AgentDispatchHubItem(projectId: 'd', title: '项目丁', running: false),
      AgentDispatchHubItem(projectId: 'c', title: '项目丙', running: true),
    ]);

    expect(
      ordered.map((item) => item.projectId).toList(),
      equals(['a', 'c', 'b', 'd']),
    );
  });

  test('总览先跟随左上角项目顺序，再把运行中项目稳定前置', () {
    final orderedProjects = orderAgentDispatchHubProjects(
      const [
        ProjectEntry(id: 'b', title: '项目乙', updatedAt: 0, revision: 0),
        ProjectEntry(id: 'a', title: '项目甲', updatedAt: 0, revision: 0),
        ProjectEntry(id: 'c', title: '项目丙', updatedAt: 0, revision: 0),
      ],
      sortMode: ProjectSortMode.name,
      pinnedProjectIds: const ['c'],
      lastUsedAtByProjectId: const {},
    );
    final ordered = orderAgentDispatchHubItems([
      for (final project in orderedProjects)
        AgentDispatchHubItem(
          projectId: project.id,
          title: project.title,
          running: project.id == 'a',
        ),
    ]);

    expect(
      ordered.map((item) => item.projectId).toList(),
      equals(['a', 'c', 'b']),
    );
  });

  testWidgets('总览列出运行中项目的进度分数', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AgentDispatchHubView(
          items: const [
            AgentDispatchHubItem(
              projectId: 'a',
              title: '项目甲',
              running: true,
              progressLabel: '3/10',
              progressFraction: 0.3,
            ),
            AgentDispatchHubItem(
              projectId: 'b',
              title: '项目乙',
              running: false,
              isCurrent: true,
            ),
          ],
          onClose: () {},
          onOpenProject: (_) {},
          onRunProject: (_) async {},
          onStopProject: (_) async {},
        ),
      ),
    );

    expect(find.text('Agent 调度总览（1 个运行中）'), findsOneWidget);
    expect(find.text('项目甲'), findsOneWidget);
    expect(find.text('运行中 · 3/10'), findsOneWidget);
    expect(find.text('项目乙'), findsOneWidget);
    expect(find.text('未运行'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    expect(find.text('查看'), findsOneWidget);
    expect(find.text('打开'), findsOneWidget);
    expect(find.text('停止'), findsOneWidget);
    expect(find.text('运行'), findsOneWidget);
  });

  test('总览文案包含标题、模型与批次/本卡耗时', () {
    final overview = AgentDispatchHubOverview.running(
      liveCardLabel: '2/5',
      currentTitle: 'Agent 调度总览可以显示更多的信息',
      phaseLabel: 'Implement',
      engine: 'cursor',
      model: 'composer-2.5',
      batchStartedAt: DateTime(2026, 8, 18, 18, 0, 0),
      cardStartedAt: DateTime(2026, 8, 18, 18, 10, 0),
      now: DateTime(2026, 8, 18, 18, 12, 30),
    );

    expect(overview.statusLine, 'Running · Implement · 2/5');
    expect(overview.cardTitle, 'Agent 调度总览可以显示更多的信息');
    expect(overview.engineModelLabel, 'Cursor SDK · composer-2.5');
    expect(overview.modelDetailLabel, isEmpty);
    expect(overview.elapsedLabel, 'Batch 12m 30s · This card 2m 30s');
  });

  test('总览文案包含上下文长度与快速模式', () {
    final overview = AgentDispatchHubOverview.running(
      liveCardLabel: '1/2',
      currentTitle: '卡片',
      phaseLabel: 'Implement',
      engine: 'cursor',
      model: 'composer-2.5',
      modelParams: const {
        'fast': 'false',
        'reasoning_effort': 'medium',
        'context': '64k',
      },
    );

    expect(overview.engineModelLabel, 'Cursor SDK · composer-2.5');
    expect(
      overview.modelDetailLabel,
      'Context 64k · Fast mode Off · Reasoning effort medium',
    );
  });

  test('overview shows Default when context is the API default', () {
    final overview = AgentDispatchHubOverview.running(
      liveCardLabel: '1/2',
      currentTitle: 'Card',
      phaseLabel: 'Implement',
      engine: 'cursor',
      model: 'composer-2.5',
      modelParams: const {
        'fast': 'false',
        'context': 'default',
      },
    );

    expect(
      overview.modelDetailLabel,
      'Context Default · Fast mode Off',
    );
  });

  test('overview does not invent 64k when context was omitted', () {
    final overview = AgentDispatchHubOverview.running(
      liveCardLabel: '1/2',
      currentTitle: 'Card',
      phaseLabel: 'Implement',
      engine: 'codex',
      model: 'gpt-5.5',
      modelParams: const {
        'model_reasoning_effort': 'medium',
      },
    );

    expect(overview.modelDetailLabel, 'Reasoning effort medium');
    expect(overview.modelDetailLabel.contains('64k'), isFalse);
  });

  testWidgets('总览列出当前卡片标题、模型与运行时间', (tester) async {
    final batchStarted = DateTime.now().subtract(const Duration(minutes: 12));
    final cardStarted = DateTime.now().subtract(const Duration(minutes: 2));
    await tester.pumpWidget(
      MaterialApp(
        home: AgentDispatchHubView(
          items: [
            AgentDispatchHubItem(
              projectId: 'a',
              title: '项目甲',
              running: true,
              progressLabel: '1/3',
              progressFraction: 0.0,
              currentTitle: 'Agent 调度总览可以显示更多的信息',
              phaseLabel: 'Implement',
              engine: 'cursor',
              model: 'composer-2.5',
              modelParams: const {
                'fast': 'true',
                'context': '272k',
              },
              batchStartedAt: batchStarted,
              cardStartedAt: cardStarted,
            ),
          ],
          onClose: () {},
          onOpenProject: (_) {},
          onRunProject: (_) async {},
          onStopProject: (_) async {},
        ),
      ),
    );

    expect(find.text('Running · Implement · 1/3'), findsOneWidget);
    expect(find.text('Agent 调度总览可以显示更多的信息'), findsOneWidget);
    expect(find.text('Cursor SDK · composer-2.5'), findsOneWidget);
    expect(find.text('Context 272k · Fast mode On'), findsOneWidget);
    expect(find.textContaining('Batch'), findsOneWidget);
    expect(find.textContaining('This card'), findsOneWidget);
  });

  testWidgets('总览可直接点运行与停止', (tester) async {
    final ran = <String>[];
    final stopped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AgentDispatchHubView(
          items: const [
            AgentDispatchHubItem(
              projectId: 'a',
              title: '项目甲',
              running: false,
            ),
            AgentDispatchHubItem(
              projectId: 'b',
              title: '项目乙',
              running: true,
              progressLabel: '1/2',
              progressFraction: 0.5,
            ),
          ],
          onClose: () {},
          onOpenProject: (_) {},
          onRunProject: (id) async => ran.add(id),
          onStopProject: (id) async => stopped.add(id),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('agent-dispatch-hub-run-a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-dispatch-hub-stop-b')));
    await tester.pump();

    expect(ran, equals(['a']));
    expect(stopped, equals(['b']));
  });
}
