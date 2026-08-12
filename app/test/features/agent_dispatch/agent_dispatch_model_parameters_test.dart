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

    expect(find.text('快速模式（Fast）'), findsOneWidget);
    expect(find.text('思考程度（Reasoning effort）'), findsOneWidget);
    expect(find.text('API 默认（On）'), findsOneWidget);
  });
}
