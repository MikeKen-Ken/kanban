import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_config.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_model_controls.dart';

void main() {
  testWidgets('model controls stack on a phone width', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: AgentDispatchModelControls(
            models: const [
              AgentDispatchModelInfo(id: 'model', displayName: 'A model'),
            ],
            modelId: 'model',
            parameters: const [
              AgentDispatchModelParameter(
                id: 'reasoning_effort',
                options: [
                  AgentDispatchModelParameterOption(value: 'medium'),
                ],
              ),
            ],
            defaultVariant: null,
            values: const {},
            busy: false,
            onModelChanged: (_) {},
            onParameterChanged: (_, __) {},
            onRefresh: () {},
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('A model'), findsOneWidget);
    expect(find.text('Reasoning effort'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Refresh models')).dy,
      greaterThan(tester.getTopLeft(find.text('A model')).dy),
    );
  });
}
