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
            onChanged: ({
              agentEngine,
              agentModelId,
              agentModelParamValues,
              agentAllowDirtyWorkspace,
              agentEnableSandbox,
            }) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('允许脏工作区'), findsOneWidget);
    expect(find.text('开沙箱'), findsOneWidget);
    expect(find.textContaining('未提交改动'), findsNothing);
    expect(find.textContaining('沿用工作台'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    final row = tester.widget<Row>(
      find.descendant(
        of: find.byType(CardDetailAgentModelSection),
        matching: find.byType(Row),
      ).first,
    );
    expect(row.children.length, greaterThan(4));
  });
}
