import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kanban/common/app_snack_bar.dart';
import 'package:kanban/features/project/project_theme.dart';

void main() {
  testWidgets('showAppSnackBar 在顶部展示主题色提示', (tester) async {
    final theme = buildKanbanTheme(
      projectThemeForId(kDefaultProjectThemeId),
      Brightness.light,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showAppSnackBar(context, message: '顶部提示'),
                child: const Text('触发'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('触发'));
    await tester.pump(); // 开始 SnackBar 动画
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('顶部提示'), findsOneWidget);

    final snackFinder = find.byType(SnackBar);
    expect(snackFinder, findsOneWidget);

    final snackBar = tester.widget<SnackBar>(snackFinder);
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(snackBar.dismissDirection, DismissDirection.up);

    final margin = snackBar.margin! as EdgeInsets;
    // 大 bottom margin：贴顶而非贴底
    expect(margin.bottom, greaterThan(200));

    final scheme = theme.colorScheme;
    final material = tester.widget<Material>(
      find.descendant(
        of: snackFinder,
        matching: find.byType(Material),
      ).first,
    );
    expect(material.color, scheme.primaryContainer);
  });

  testWidgets('showAppSnackBar 在刘海屏避开顶部与底部安全区', (tester) async {
    const viewTop = 59.0;
    const viewBottom = 34.0;
    const surface = Size(390, 844);

    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding =
        const FakeViewPadding(top: viewTop, bottom: viewBottom);
    // 模拟 Scaffold body / SafeArea 已消费 padding.top
    tester.view.padding = const FakeViewPadding(bottom: viewBottom);
    addTearDown(tester.view.reset);

    final theme = buildKanbanTheme(
      projectThemeForId(kDefaultProjectThemeId),
      Brightness.light,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showAppSnackBar(context, message: '安全区提示'),
                child: const Text('触发'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('触发'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final snackFinder = find.byType(SnackBar);
    expect(snackFinder, findsOneWidget);

    final snackBar = tester.widget<SnackBar>(snackFinder);
    final margin = snackBar.margin! as EdgeInsets;
    // bottom margin 已扣除 viewPadding.bottom，仍保持大间距贴顶
    expect(margin.bottom, greaterThan(200));
    expect(
      margin.bottom,
      closeTo(surface.height - viewBottom - (viewTop + 12) - 56, 1),
    );

    final barMaterial = find.descendant(
      of: snackFinder,
      matching: find.byType(Material),
    ).first;
    final top = tester.getTopLeft(barMaterial).dy;
    // 可视条须落在顶部安全区下方，且仍靠近屏幕上方
    expect(top, greaterThanOrEqualTo(viewTop));
    expect(top, lessThan(viewTop + 80));
  });
}
