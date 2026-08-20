import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_config.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_model_parameters.dart';

void main() {
  testWidgets('快速模式与思考程度分别展示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentDispatchModelParameters(
            parameters: const [
              AgentDispatchModelParameter(
                id: 'fast',
                displayName: 'Fast',
                options: [
                  AgentDispatchModelParameterOption(
                    value: 'true',
                    displayName: 'On',
                  ),
                  AgentDispatchModelParameterOption(
                    value: 'false',
                    displayName: 'Off',
                  ),
                ],
              ),
              AgentDispatchModelParameter(
                id: 'reasoning_effort',
                displayName: 'Reasoning effort',
                options: [
                  AgentDispatchModelParameterOption(value: 'low'),
                  AgentDispatchModelParameterOption(value: 'medium'),
                  AgentDispatchModelParameterOption(value: 'high'),
                ],
              ),
            ],
            defaultVariant: const AgentDispatchModelVariant(
              displayName: 'Fast',
              isDefault: true,
              params: {'fast': 'true'},
            ),
            values: const {},
            enabled: true,
            onChanged: (_, __) {},
          ),
        ),
      ),
    );

    expect(find.text('快速模式'), findsOneWidget);
    expect(find.text('思考程度'), findsOneWidget);
    expect(find.text('API 默认（On）'), findsOneWidget);
  });

  test('preferredAgentDispatchModelParamValues 关闭快速模式并选 Medium', () {
    const parameters = [
      AgentDispatchModelParameter(
        id: 'fast',
        options: [
          AgentDispatchModelParameterOption(value: 'true'),
          AgentDispatchModelParameterOption(value: 'false'),
        ],
      ),
      AgentDispatchModelParameter(
        id: 'reasoning_effort',
        options: [
          AgentDispatchModelParameterOption(value: 'low'),
          AgentDispatchModelParameterOption(value: 'medium'),
          AgentDispatchModelParameterOption(value: 'high'),
        ],
      ),
      AgentDispatchModelParameter(
        id: 'context',
        options: [
          AgentDispatchModelParameterOption(value: '64k'),
          AgentDispatchModelParameterOption(value: '272k'),
        ],
      ),
    ];
    expect(
      preferredAgentDispatchModelParamValues(parameters),
      {'fast': 'false', 'reasoning_effort': 'medium', 'context': '64k'},
    );
  });

  test('filterAgentDispatchModelParamValues 目录未加载时保留原值', () {
    expect(
      filterAgentDispatchModelParamValues(
        const {'fast': 'false', 'context': '64k'},
        const [],
      ),
      {'fast': 'false', 'context': '64k'},
    );
  });
}
