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
}
