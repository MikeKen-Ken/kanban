import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kanban/features/kanban/card_drag.dart';

void main() {
  group('feedbackCenterDragAnchorStrategy', () {
    testWidgets('返回反馈宽度与卡片高度的中心点', (tester) async {
      late Offset anchor;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                height: 120,
                child: Draggable<int>(
                  data: 1,
                  dragAnchorStrategy: (draggable, context, position) {
                    anchor = feedbackCenterDragAnchorStrategy(
                      draggable,
                      context,
                      position,
                      feedbackWidth: 280,
                    );
                    return anchor;
                  },
                  feedback: const SizedBox(width: 280, height: 120),
                  child: const SizedBox(
                    key: Key('drag-child'),
                    width: 280,
                    height: 120,
                    child: ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(
        find.byKey(const Key('drag-child')),
        const Offset(40, 30),
      );
      expect(anchor, const Offset(140, 60));
    });

    testWidgets('扣除列表 bottom margin 后对准可见本体中心', (tester) async {
      late Offset anchor;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                height: 128,
                child: Draggable<int>(
                  data: 1,
                  dragAnchorStrategy: (draggable, context, position) {
                    anchor = feedbackCenterDragAnchorStrategy(
                      draggable,
                      context,
                      position,
                      feedbackWidth: 280,
                      listBottomMargin: 8,
                    );
                    return anchor;
                  },
                  feedback: const SizedBox(width: 280, height: 120),
                  child: const SizedBox(
                    key: Key('drag-child-margin'),
                    width: 280,
                    height: 128,
                    child: ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(
        find.byKey(const Key('drag-child-margin')),
        const Offset(40, 30),
      );
      expect(anchor, const Offset(140, 60));
    });
  });

  group('shouldSuppressCardTapAfterPress', () {
    test('拖拽已开始则一律抑制', () {
      expect(
        shouldSuppressCardTapAfterPress(
          heldMs: 10,
          dragLongPressMs: 500,
          dragStarted: true,
        ),
        isTrue,
      );
    });

    test('即时拖拽模式不因按住时长抑制', () {
      expect(
        shouldSuppressCardTapAfterPress(
          heldMs: 800,
          dragLongPressMs: 0,
          dragStarted: false,
        ),
        isFalse,
      );
    });

    test('短按不抑制，接近阈值则抑制', () {
      expect(
        shouldSuppressCardTapAfterPress(
          heldMs: 50,
          dragLongPressMs: 500,
          dragStarted: false,
        ),
        isFalse,
      );
      // 500 * 0.35 = 175，夹在 [120, 500]
      expect(
        shouldSuppressCardTapAfterPress(
          heldMs: 175,
          dragLongPressMs: 500,
          dragStarted: false,
        ),
        isTrue,
      );
    });

    test('很短的拖拽延迟时阈值至少 120ms', () {
      // 200 * 0.35 = 70 → clamp 到 120
      expect(
        shouldSuppressCardTapAfterPress(
          heldMs: 100,
          dragLongPressMs: 200,
          dragStarted: false,
        ),
        isFalse,
      );
      expect(
        shouldSuppressCardTapAfterPress(
          heldMs: 120,
          dragLongPressMs: 200,
          dragStarted: false,
        ),
        isTrue,
      );
    });
  });

  group('CardDragInteractionBlocker', () {
    testWidgets('长按交互区不启动 CardLongPressDraggable', (tester) async {
      var dragStarted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                height: 120,
                child: CardLongPressDraggable<int>(
                  data: 1,
                  delay: const Duration(milliseconds: 200),
                  onDragStarted: () => dragStarted = true,
                  feedback: const SizedBox(width: 280, height: 120),
                  child: Row(
                    children: [
                      CardDragInteractionBlocker(
                        child: SizedBox(
                          key: const Key('blocked'),
                          width: 48,
                          height: 48,
                          child: ColoredBox(color: Colors.red.shade200),
                        ),
                      ),
                      const Expanded(
                        child: SizedBox(
                          key: Key('draggable'),
                          height: 48,
                          child: ColoredBox(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final blocked = find.byKey(const Key('blocked'));
      final center = tester.getCenter(blocked);
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 250));
      await gesture.up();
      await tester.pump();

      expect(dragStarted, isFalse);
    });

    testWidgets('即时拖拽在交互区按下不启动', (tester) async {
      var dragStarted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                height: 120,
                child: CardDraggable<int>(
                  data: 1,
                  onDragStarted: () => dragStarted = true,
                  feedback: const SizedBox(width: 280, height: 120),
                  child: CardDragInteractionBlocker(
                    child: SizedBox(
                      key: const Key('blocked-immediate'),
                      width: 280,
                      height: 120,
                      child: ColoredBox(color: Colors.green.shade200),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(
        find.byKey(const Key('blocked-immediate')),
        const Offset(40, 0),
      );
      expect(dragStarted, isFalse);
    });
  });

  group('卡片上下文菜单触控入口', () {
    test('Android / iOS 视为触控主平台，桌面否', () {
      expect(isTouchPrimaryPlatform(TargetPlatform.android), isTrue);
      expect(isTouchPrimaryPlatform(TargetPlatform.iOS), isTrue);
      expect(isTouchPrimaryPlatform(TargetPlatform.windows), isFalse);
      expect(isTouchPrimaryPlatform(TargetPlatform.macOS), isFalse);
      expect(isTouchPrimaryPlatform(TargetPlatform.linux), isFalse);
    });

    test('仅即时拖拽启用长按菜单', () {
      expect(
        shouldEnableLongPressCardContextMenu(immediateDrag: true),
        isTrue,
      );
      expect(
        shouldEnableLongPressCardContextMenu(immediateDrag: false),
        isFalse,
      );
    });

    test('触控平台展示「⋯」菜单按钮，桌面不展示', () {
      expect(shouldShowCardContextMenuButton(TargetPlatform.android), isTrue);
      expect(shouldShowCardContextMenuButton(TargetPlatform.iOS), isTrue);
      expect(shouldShowCardContextMenuButton(TargetPlatform.windows), isFalse);
      expect(shouldShowCardContextMenuButton(TargetPlatform.macOS), isFalse);
    });
  });
}
