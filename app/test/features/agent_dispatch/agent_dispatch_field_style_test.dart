import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_card_limit_field.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_field_style.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_repository_field.dart';

void main() {
  test('浅色主题下输入文字亮度低于占位符', () {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    );
    final text = agentDispatchFieldTextStyle(theme).color!;
    final hint = agentDispatchFieldHintStyle(theme).color!;

    expect(text.computeLuminance(), lessThan(hint.computeLuminance()));
  });

  testWidgets('仓库路径输入框区分输入色与占位符', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentDispatchRepositoryField(
            controller: TextEditingController(),
            paths: const [],
            enabled: true,
            onChanged: (_) {},
            onPickDirectory: () {},
            onDeletePath: (_) {},
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style?.color, isNotNull);
    expect(field.decoration?.hintStyle?.color, isNotNull);
    expect(
      field.style!.color!.computeLuminance(),
      lessThan(field.decoration!.hintStyle!.color!.computeLuminance()),
    );
  });

  testWidgets('卡片上限输入框区分输入色与占位符', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentDispatchCardLimitField(
            controller: TextEditingController(),
            useMax: false,
            enabled: true,
            onMaxChanged: (_) {},
            onCountChanged: (_) {},
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.style!.color!.computeLuminance(),
      lessThan(field.decoration!.hintStyle!.color!.computeLuminance()),
    );
  });
}
