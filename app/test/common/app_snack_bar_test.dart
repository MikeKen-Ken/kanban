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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('顶部提示'), findsOneWidget);

    final alignFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Align && widget.alignment == Alignment.topCenter,
    );
    expect(alignFinder, findsOneWidget);

    final scheme = theme.colorScheme;
    final material = tester.widget<Material>(
      find.descendant(
        of: alignFinder,
        matching: find.byType(Material),
      ).first,
    );
    expect(material.color, scheme.primaryContainer);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('showAppSnackBar 空消息或纯空白不展示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                FilledButton(
                  onPressed: () => showAppSnackBar(context, message: ''),
                  child: const Text('空消息'),
                ),
                FilledButton(
                  onPressed: () => showAppSnackBar(context, message: '   '),
                  child: const Text('空白消息'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final topAlign = find.byWidgetPredicate(
      (widget) =>
          widget is Align && widget.alignment == Alignment.topCenter,
    );

    await tester.tap(find.text('空消息'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(topAlign, findsNothing);

    await tester.tap(find.text('空白消息'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(topAlign, findsNothing);
  });

  testWidgets('showAppSnackBar 支持操作按钮', (tester) async {
    var actionPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showAppSnackBar(
                  context,
                  message: '可撤销',
                  action: SnackBarAction(
                    label: '撤销',
                    onPressed: () => actionPressed = true,
                  ),
                ),
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

    expect(find.text('可撤销'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(actionPressed, isTrue);
  });

  testWidgets('showAppSnackBar clearExisting 替换已有提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                FilledButton(
                  onPressed: () =>
                      showAppSnackBar(context, message: '第一条'),
                  child: const Text('第一条'),
                ),
                FilledButton(
                  onPressed: () => showAppSnackBar(
                    context,
                    message: '第二条',
                    clearExisting: true,
                  ),
                  child: const Text('第二条'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('第一条'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('第一条'), findsOneWidget);

    await tester.tap(find.text('第二条'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
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
