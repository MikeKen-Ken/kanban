import 'package:flutter_test/flutter_test.dart';

import 'package:kanban/features/project/project_quick_switch.dart';

void main() {
  group('projectQuickSwitchIndex', () {
    test('空列表返回 0', () {
      expect(
        projectQuickSwitchIndex(
          startIndex: 2,
          dy: 40,
          itemExtent: 44,
          length: 0,
        ),
        0,
      );
    });

    test('按位移步进切换并夹紧边界', () {
      expect(
        projectQuickSwitchIndex(
          startIndex: 1,
          dy: 44,
          itemExtent: 44,
          length: 4,
        ),
        2,
      );
      expect(
        projectQuickSwitchIndex(
          startIndex: 1,
          dy: -50,
          itemExtent: 44,
          length: 4,
        ),
        0,
      );
      expect(
        projectQuickSwitchIndex(
          startIndex: 1,
          dy: 200,
          itemExtent: 44,
          length: 4,
        ),
        3,
      );
    });

    test('半格内保持当前项', () {
      expect(
        projectQuickSwitchIndex(
          startIndex: 2,
          dy: 20,
          itemExtent: 44,
          length: 5,
        ),
        2,
      );
      expect(
        projectQuickSwitchIndex(
          startIndex: 2,
          dy: 22,
          itemExtent: 44,
          length: 5,
        ),
        3,
      );
    });
  });
}
