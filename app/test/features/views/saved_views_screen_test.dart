import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/views/views.dart';

void main() {
  const view = SavedView(
    id: 'focus',
    name: '今日重点',
    filter: FilterSpec(priorities: ['high']),
    createdAt: 1,
    updatedAt: 2,
  );

  testWidgets('空列表仍提供显示全部入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SavedViewsScreen(
          views: const [],
          onRename: (_, __) async {},
          onDelete: (_) async {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('saved-view-show-all')), findsOneWidget);
    expect(find.text('Show all'), findsOneWidget);
    expect(find.text('No saved views yet'), findsOneWidget);
    expect(find.textContaining('Set a scope and filters in Search'), findsOneWidget);
  });

  testWidgets('可重命名并删除保存视图', (tester) async {
    String? renamed;
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SavedViewsScreen(
          views: const [view],
          onRename: (_, name) async => renamed = name,
          onDelete: (_) async => deleted = true,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Manage "今日重点"'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('saved-view-name')),
      '本周重点',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(renamed, '本周重点');
    expect(find.text('本周重点'), findsOneWidget);
    expect(find.text('Renamed to "本周重点"'), findsOneWidget);

    await tester.tap(find.byTooltip('Manage "本周重点"'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cards will not be affected'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('No saved views yet'), findsOneWidget);
    expect(find.text('Show all'), findsOneWidget);
  });

  testWidgets('点击保存视图会将其返回调用页', (tester) async {
    SavedView? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              selected = await Navigator.of(context).push<SavedView>(
                MaterialPageRoute<SavedView>(
                  builder: (_) => SavedViewsScreen(
                    views: const [view],
                    onRename: (_, __) async {},
                    onDelete: (_) async {},
                  ),
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日重点'));
    await tester.pumpAndSettle();

    expect(selected?.id, 'focus');
  });

  testWidgets('点击显示全部会返回清除筛选入口', (tester) async {
    SavedView? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              selected = await Navigator.of(context).push<SavedView>(
                MaterialPageRoute<SavedView>(
                  builder: (_) => SavedViewsScreen(
                    views: const [view],
                    onRename: (_, __) async {},
                    onDelete: (_) async {},
                  ),
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saved-view-show-all')));
    await tester.pumpAndSettle();

    expect(selected?.isShowAll, isTrue);
    expect(selected?.filter.hasFilters, isFalse);
  });
}
