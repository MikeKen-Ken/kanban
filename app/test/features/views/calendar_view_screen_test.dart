import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kanban/features/views/views.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  CardReference dueOn(DateTime day, {required String title}) {
    final end = DateTime(day.year, day.month, day.day, 23, 59, 59);
    return CardReference(
      projectId: 'p1',
      projectName: '项目甲',
      columnId: 'todo',
      columnName: '待办',
      cardId: title,
      title: title,
      dueDate: end.millisecondsSinceEpoch,
    );
  }

  Widget buildScreen({
    required List<CardReference> cards,
    Size size = const Size(1200, 800),
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: CalendarViewScreen(
          loadCards: () async => cards,
          onOpen: (_) async {},
          onToggleCompleted: (_) async {},
          onChangeDueDate: (_, __) async {},
          onCreateForDay: (_) async {},
        ),
      ),
    );
  }

  testWidgets('桌面宽屏下日历格子高度受控，空状态不占满半屏', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildScreen(cards: const []));
    await tester.pumpAndSettle();

    expect(find.text('日历'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-day-empty')), findsOneWidget);
    expect(find.textContaining('暂无到期任务'), findsOneWidget);

    final emptyBox = tester.getRect(
      find.byKey(const ValueKey('calendar-day-empty')),
    );
    // 空状态应为顶部紧凑文案，而非占满下方半屏的居中大块。
    expect(emptyBox.height, lessThan(48));
    expect(emptyBox.top, lessThan(520));

    // 日期格：宽屏下单格高度应明显小于正方形铺满时的 ~160px。
    final cellMaterial = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(Material),
    );
    expect(cellMaterial, findsWidgets);
    final cellSize = tester.getSize(cellMaterial.first);
    expect(cellSize.height, lessThan(56));
    expect(cellSize.height, greaterThan(32));
  });

  testWidgets('选中有任务的日期时在底部列表展示', (tester) async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final cards = [
      dueOn(day, title: '今天要做'),
      dueOn(day.add(const Duration(days: 2)), title: '后天任务'),
    ];

    await tester.pumpWidget(buildScreen(cards: cards));
    await tester.pumpAndSettle();

    expect(find.text('今天要做'), findsOneWidget);
    expect(find.text('后天任务'), findsNothing);
    expect(find.byKey(const ValueKey('calendar-day-empty')), findsNothing);
  });

  testWidgets('今天始终有标识，选中其他日期后日期数字仍位于格子中央', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    await tester.pumpWidget(buildScreen(cards: const []));
    await tester.pumpAndSettle();

    final todayMarker = find.byKey(const ValueKey('calendar-today-marker'));
    expect(todayMarker, findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('今天')), findsOneWidget);

    final todayCell = find
        .ancestor(
          of: todayMarker,
          matching: find.byType(Material),
        )
        .first;
    expect(todayCell, findsOneWidget);
    final today = DateTime.now();
    final todayNumber = find.descendant(
      of: todayCell,
      matching: find.text('${today.day}'),
    );
    expect(todayNumber, findsOneWidget);

    final cellRect = tester.getRect(todayCell);
    final numberRect = tester.getRect(todayNumber);
    expect((numberRect.center.dx - cellRect.center.dx).abs(), lessThan(1));
    expect((numberRect.center.dy - cellRect.center.dy).abs(), lessThan(1));

    final cells = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(Material),
    );
    final todayElement = todayCell.evaluate().single;
    final anotherCell = cells.evaluate().firstWhere(
          (element) => element != todayElement,
        );
    await tester.tap(find.byWidget(anotherCell.widget));
    await tester.pumpAndSettle();

    expect(todayMarker, findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('今天')), findsOneWidget);
  });

  testWidgets('本月与非本月日期使用不同的格子底色', (tester) async {
    await tester.pumpWidget(buildScreen(cards: const []));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(GridView)));
    final cells = find
        .descendant(
          of: find.byType(GridView),
          matching: find.byType(Material),
        )
        .evaluate()
        .map((element) => element.widget as Material)
        .toList();

    expect(
      cells.where((cell) => cell.color == theme.colorScheme.surfaceContainerLow),
      isNotEmpty,
    );
    expect(
      cells.where(
        (cell) => cell.color == theme.colorScheme.surfaceContainerHighest,
      ),
      isNotEmpty,
    );
  });
}
