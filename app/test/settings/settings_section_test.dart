import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/settings/settings_section.dart';

void main() {
  testWidgets('单层导航卡只显示一个入口并支持整卡点击', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsNavigationCard(
            icon: Icons.label_outline,
            title: '标签',
            subtitle: '3 个自定义标签 · 随工作区同步',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('标签'), findsOneWidget);
    expect(find.text('标签管理'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await tester.tap(find.byType(SettingsNavigationCard));

    expect(tapped, isTrue);
  });
}
