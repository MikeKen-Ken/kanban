import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_hub.dart';
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
  });
}
