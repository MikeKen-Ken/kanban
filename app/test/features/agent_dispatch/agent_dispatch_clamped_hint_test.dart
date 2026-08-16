import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_clamped_hint.dart';

void main() {
  test('开关打开时不提醒', () {
    expect(
      agentDispatchClampedParamsHint(
        allowHighReasoning: true,
        values: {'reasoning_effort': 'high', 'context': '272k'},
      ),
      isNull,
    );
  });

  test('开关关闭且选了高推理或大上下文时提醒会被压档', () {
    expect(
      agentDispatchClampedParamsHint(
        allowHighReasoning: false,
        values: {'reasoning_effort': 'high'},
      ),
      contains('推理会压到 medium'),
    );
    expect(
      agentDispatchClampedParamsHint(
        allowHighReasoning: false,
        values: {'context': '272k'},
      ),
      contains('上下文会压到 64k'),
    );
    final both = agentDispatchClampedParamsHint(
      allowHighReasoning: false,
      values: {
        'reasoning_effort': 'high',
        'context': '272k',
      },
    );
    expect(both, contains('推理会压到 medium'));
    expect(both, contains('上下文会压到 64k'));
    expect(both, contains('允许高费用档位'));
  });

  test('开关关闭但参数本就省档时不提醒', () {
    expect(
      agentDispatchClampedParamsHint(
        allowHighReasoning: false,
        values: {'reasoning_effort': 'medium', 'context': '64k', 'fast': 'false'},
      ),
      isNull,
    );
  });

  testWidgets('有提醒时展示文案', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentDispatchClampedParamHint(
            allowHighReasoning: false,
            values: {'context': '272k'},
          ),
        ),
      ),
    );
    expect(find.textContaining('上下文会压到 64k'), findsOneWidget);
  });
}
