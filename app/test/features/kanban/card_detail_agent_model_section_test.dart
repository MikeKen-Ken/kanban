import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/card_detail_agent_model_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('卡片 Agent 配置单行排布且脏工作区无解释', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardDetailAgentModelSection(
            agentEngine: null,
            agentModelId: null,
            agentModelParamValues: const {},
            agentAllowDirtyWorkspace: null,
            agentEnableSandbox: null,
            agentRequireTests: null,
            onChanged: ({
              agentEngine,
              agentModelId,
              agentModelParamValues = const {},
              agentAllowDirtyWorkspace,
              agentEnableSandbox,
              agentRequireTests,
            }) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Allow dirty workspace'), findsOneWidget);
    expect(find.text('Enable sandbox'), findsOneWidget);
    expect(find.text('Tests required'), findsOneWidget);
    final requireTestsCheckbox = tester.widgetList<Checkbox>(
      find.descendant(
        of: find.ancestor(
          of: find.text('Tests required'),
          matching: find.byType(InkWell),
        ),
        matching: find.byType(Checkbox),
      ),
    );
    expect(requireTestsCheckbox.single.value, isFalse);
    expect(find.textContaining('未提交改动'), findsNothing);
    expect(find.textContaining('沿用工作台'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    final row = tester.widget<Row>(
      find
          .descendant(
            of: find.byType(CardDetailAgentModelSection),
            matching: find.byType(Row),
          )
          .first,
    );
    expect(row.children.length, greaterThan(4));

    final fields = tester.widgetList<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(fields, isNotEmpty);
    for (final field in fields) {
      expect(field.decoration.labelStyle?.fontSize, 12.5);
    }
  });
}
