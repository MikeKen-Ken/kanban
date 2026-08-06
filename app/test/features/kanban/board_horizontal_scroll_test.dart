import 'package:flutter/material.dart';
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
}
