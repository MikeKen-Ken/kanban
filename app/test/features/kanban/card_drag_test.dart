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
}
