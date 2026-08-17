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

  testWidgets('二级分类页展示分组内的导航项', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsCategoryScreen(
          title: '当前项目',
          children: const [
            SettingsNavigationTile(title: '项目设置', onTap: _noop),
            SettingsNavigationTile(title: '活动历史', onTap: _noop),
          ],
        ),
      ),
    );

    expect(find.text('当前项目'), findsWidgets);
    expect(find.text('项目设置'), findsOneWidget);
    expect(find.text('活动历史'), findsOneWidget);
  });
}

void _noop() {}

