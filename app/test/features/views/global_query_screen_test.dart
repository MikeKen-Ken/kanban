import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/views/views.dart';

void main() {
  final cards = [
    const CardReference(
      projectId: 'work',
      projectName: '工作',
      columnId: 'todo',
      columnName: '待办',
      cardId: 'work-card',
      title: '发布新版本',
      priority: 'high',
    ),
    const CardReference(
      projectId: 'home',
      projectName: '家庭',
      columnId: 'todo',
      columnName: '待办',
      cardId: 'home-card',
      title: '购买灯泡',
    ),
  ];

  Widget buildScreen({
    List<SavedView> views = const [],
    PersistSavedView? onSaveView,
  }) {
    return MaterialApp(
      home: GlobalQueryScreen(
        loadCards: () async => cards,
        onOpen: (_) async {},
        onToggleCompleted: (_) async {},
        labels: const {},
        savedViews: () => views,
        onSaveView: onSaveView ?? (_, __, ___) async {},
        onDeleteView: (_) async {},
      ),
    );
  }

  testWidgets('可按关键词和项目筛选跨项目卡片', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('发布新版本'), findsOneWidget);
    expect(find.text('购买灯泡'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('global-query-search')),
      '发布',
    );
    await tester.pump();
    expect(find.text('发布新版本'), findsOneWidget);
    expect(find.text('购买灯泡'), findsNothing);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();
    await tester.tap(find.byTooltip('筛选与排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('家庭'));
    await tester.ensureVisible(find.text('应用筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();

    expect(find.text('发布新版本'), findsNothing);
    expect(find.text('购买灯泡'), findsOneWidget);
  });

  testWidgets('应用保存视图后恢复关键词和筛选条件', (tester) async {
    const view = SavedView(
      id: 'important',
      name: '工作重点',
      filter: FilterSpec(
        keyword: '发布',
        projectIds: ['work'],
        sortField: CardSortField.priority,
        sortDirection: SortDirection.descending,
      ),
    );
    await tester.pumpWidget(buildScreen(views: const [view]));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('管理保存视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工作重点'));
    await tester.pumpAndSettle();

    final search = tester.widget<TextField>(
      find.byKey(const ValueKey('global-query-search')),
    );
    expect(search.controller!.text, '发布');
    expect(find.text('发布新版本'), findsOneWidget);
    expect(find.text('购买灯泡'), findsNothing);
    expect(find.text('已应用「工作重点」'), findsOneWidget);
  });

  testWidgets('保存当前查询并提供明确反馈', (tester) async {
    String? savedName;
    FilterSpec? savedFilter;
    await tester.pumpWidget(
      buildScreen(
        onSaveView: (_, name, filter) async {
          savedName = name;
          savedFilter = filter;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('global-query-search')),
      '灯泡',
    );
    await tester.tap(find.byTooltip('保存当前视图'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('global-view-name')),
      '家庭采购',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(savedName, '家庭采购');
    expect(savedFilter?.keyword, '灯泡');
    expect(find.text('已保存视图「家庭采购」'), findsOneWidget);
  });
}
