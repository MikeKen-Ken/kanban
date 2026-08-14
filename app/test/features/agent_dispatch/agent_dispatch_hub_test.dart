import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_hub.dart';

void main() {
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
