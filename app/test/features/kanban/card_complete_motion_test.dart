import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/card_complete_checkbox.dart';
import 'package:kanban/features/kanban/card_complete_motion.dart';
import 'package:kanban/features/kanban/card_detail_actions_bar.dart';

void main() {
  test('飞行矩形沿弧线插值，中点高于两端', () {
    const from = Rect.fromLTWH(10, 100, 80, 40);
    const to = Rect.fromLTWH(210, 100, 80, 40);
    final mid = flightRectAt(from: from, to: to, t: 0.5, arcHeight: 28);
    expect(mid.center.dx, closeTo(150, 0.001));
    expect(mid.center.dy, lessThan(from.center.dy));
    expect(flightRectAt(from: from, to: to, t: 0).center, from.center);
    expect(flightRectAt(from: from, to: to, t: 1).center, to.center);
  });

  test('飞出屏幕时后半段淡出，落点可见时保持不透明', () {
    expect(flightOpacityAt(0.2, fadeOut: false), 1);
    expect(flightOpacityAt(1, fadeOut: false), 1);
    expect(flightOpacityAt(0.2, fadeOut: true), 1);
    expect(flightOpacityAt(1, fadeOut: true), 0);
    expect(flightOpacityAt(0.7, fadeOut: true), lessThan(1));
  });

  test('与屏幕重叠不足时视为不可见', () {
    const screen = Size(400, 800);
    expect(
      isRectOnScreen(const Rect.fromLTWH(10, 10, 100, 80), screen),
      isTrue,
    );
    expect(
      isRectOnScreen(const Rect.fromLTWH(500, 10, 100, 80), screen),
      isFalse,
    );
    expect(
      isRectOnScreen(const Rect.fromLTWH(390, 10, 80, 80), screen, minVisible: 48),
      isFalse,
    );
  });

  testWidgets('完成勾选等缩放回弹结束后才通知父级', (tester) async {
    var called = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardCompleteCheckbox(
            value: false,
            onChanged: (_) async {
              called += 1;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(called, 0);

    await tester.pump(CardCompleteMotion.checkbox);
    await tester.pump(const Duration(milliseconds: 1));
    expect(called, 1);
  });

  testWidgets('关闭动画时勾选立即通知父级', (tester) async {
    var called = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: CardCompleteCheckbox(
              value: false,
              onChanged: (_) async {
                called += 1;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(called, 1);
  });

  testWidgets('无起点时完成飞行直接突变', (tester) async {
    var mutated = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                playCardCompleteFlight(
                  context: context,
                  cardId: 'c1',
                  replica: const SizedBox(),
                  mutate: () async {
                    mutated += 1;
                    return null;
                  },
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(mutated, 1);
  });

  testWidgets('详情完成按钮先切到已完成再回调', (tester) async {
    var called = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardDetailCompleteButton(
            onComplete: () async {
              called += 1;
            },
          ),
        ),
      ),
    );

    expect(find.text('完成'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('card-detail-complete')));
    await tester.pump();
    expect(find.text('已完成'), findsOneWidget);
    expect(called, 0);

    await tester.pump(CardCompleteMotion.button);
    await tester.pump(const Duration(milliseconds: 1));
    expect(called, 1);
  });

  testWidgets('飞行终点优先已完成列中的卡片矩形，而不是源列占位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: 10,
              top: 40,
              width: 80,
              height: 40,
              child: CardLayoutAnchor.card(
                cardId: 'c1',
                columnId: 'todo',
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: 200,
              top: 80,
              width: 80,
              height: 40,
              child: CardLayoutAnchor.card(
                cardId: 'c1',
                columnId: 'done',
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final target = CardLayoutRegistry.instance.resolveFlightTarget(
      cardId: 'c1',
      doneColumnId: 'done',
      screenSize: const Size(800, 600),
    );
    expect(target, isNotNull);
    expect(target!.left, closeTo(200, 0.5));
    expect(target.top, closeTo(80, 0.5));
  });
}
