import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kanban/features/kanban/board_horizontal_scroll.dart';

void main() {
  group('boardHorizontalScrollDelta', () {
    test('鼠标滚轮以 dy 为主', () {
      expect(
        boardHorizontalScrollDelta(const Offset(0, 120)),
        120,
      );
    });

    test('触控板横向手势以 dx 为主', () {
      expect(
        boardHorizontalScrollDelta(const Offset(80, 10)),
        80,
      );
    });

    test('等量时优先 dy（常见滚轮）', () {
      expect(
        boardHorizontalScrollDelta(const Offset(40, 40)),
        40,
      );
    });
  });

  group('clampBoardScrollOffset', () {
    test('夹在可滚动范围内', () {
      expect(
        clampBoardScrollOffset(
          pixels: 50,
          delta: 100,
          minScrollExtent: 0,
          maxScrollExtent: 120,
        ),
        120,
      );
      expect(
        clampBoardScrollOffset(
          pixels: 10,
          delta: -40,
          minScrollExtent: 0,
          maxScrollExtent: 120,
        ),
        0,
      );
    });
  });

  group('shouldClaimBoardHorizontalWheel', () {
    test('Ctrl 按下时认领（与输入焦点无关）', () {
      expect(
        shouldClaimBoardHorizontalWheel(
          isControlPressed: true,
          isSpacePressed: false,
          isEditableFocused: false,
        ),
        isTrue,
      );
      expect(
        shouldClaimBoardHorizontalWheel(
          isControlPressed: true,
          isSpacePressed: false,
          isEditableFocused: true,
        ),
        isTrue,
      );
    });

    test('空格按下且未聚焦输入框时认领', () {
      expect(
        shouldClaimBoardHorizontalWheel(
          isControlPressed: false,
          isSpacePressed: true,
          isEditableFocused: false,
        ),
        isTrue,
      );
    });

    test('空格按下但输入框聚焦时不认领', () {
      expect(
        shouldClaimBoardHorizontalWheel(
          isControlPressed: false,
          isSpacePressed: true,
          isEditableFocused: true,
        ),
        isFalse,
      );
    });

    test('无修饰键时不认领', () {
      expect(
        shouldClaimBoardHorizontalWheel(
          isControlPressed: false,
          isSpacePressed: false,
          isEditableFocused: false,
        ),
        isFalse,
      );
    });

    test('Ctrl 优先于空格+输入焦点限制', () {
      expect(
        shouldClaimBoardHorizontalWheel(
          isControlPressed: true,
          isSpacePressed: true,
          isEditableFocused: true,
        ),
        isTrue,
      );
    });
  });

  group('isEditableTextFocused', () {
    testWidgets('无焦点时为 false', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(isEditableTextFocused(), isFalse);
    });

    testWidgets('TextField 聚焦时为 true', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(focusNode: focusNode),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      expect(isEditableTextFocused(), isTrue);
      expect(isEditableTextFocused(focusNode), isTrue);
    });

    testWidgets('非输入焦点时为 false', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              focusNode: focusNode,
              child: const SizedBox(width: 10, height: 10),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
      expect(isEditableTextFocused(), isFalse);
      expect(isEditableTextFocused(focusNode), isFalse);
    });
  });

  group('BoardHorizontalScroll 修饰键滚轮', () {
    Future<ScrollController> pumpBoard(WidgetTester tester) async {
      late ScrollController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 240,
              child: BoardHorizontalScroll(
                builder: (context, scrollController) {
                  controller = scrollController;
                  return ListView(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    children: const [
                      SizedBox(width: 800, height: 200),
                      SizedBox(width: 800, height: 200),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    Future<void> scrollAtBoard(WidgetTester tester, Offset scrollDelta) async {
      final center = tester.getCenter(find.byType(BoardHorizontalScroll));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: scrollDelta),
      );
      await tester.pump();
    }

    testWidgets('空格+滚轮横向滚动', (tester) async {
      final controller = await pumpBoard(tester);
      expect(controller.offset, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await scrollAtBoard(tester, const Offset(0, 120));
      expect(controller.offset, 120);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    });

    testWidgets('Ctrl+滚轮横向滚动（行为保留）', (tester) async {
      final controller = await pumpBoard(tester);
      expect(controller.offset, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await scrollAtBoard(tester, const Offset(0, 80));
      expect(controller.offset, 80);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('无修饰键时滚轮不横滚', (tester) async {
      final controller = await pumpBoard(tester);
      expect(controller.offset, 0);

      await scrollAtBoard(tester, const Offset(0, 120));
      expect(controller.offset, 0);
    });

    testWidgets('TextField 聚焦时空格+滚轮不横滚，且空格可输入', (tester) async {
      final textController = TextEditingController();
      addTearDown(textController.dispose);
      late ScrollController scrollController;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: textController),
                SizedBox(
                  width: 400,
                  height: 200,
                  child: BoardHorizontalScroll(
                    builder: (context, controller) {
                      scrollController = controller;
                      return ListView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        children: const [
                          SizedBox(width: 800, height: 160),
                          SizedBox(width: 800, height: 160),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(isEditableTextFocused(), isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(BoardHorizontalScroll)),
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();
      expect(scrollController.offset, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

      await tester.enterText(find.byType(TextField), 'a b');
      expect(textController.text, 'a b');
    });
  });
}
