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

  group('projectQuickSwitchIndexAtY', () {
    test('空列表返回 0', () {
      expect(
        projectQuickSwitchIndexAtY(
          localY: 80,
          itemExtent: 44,
          length: 0,
        ),
        0,
      );
    });

    test('指针落在哪一行就高亮哪一行', () {
      const extent = 44.0;
      expect(
        projectQuickSwitchIndexAtY(
          localY: 0,
          itemExtent: extent,
          length: 5,
        ),
        0,
      );
      expect(
        projectQuickSwitchIndexAtY(
          localY: extent - 0.1,
          itemExtent: extent,
          length: 5,
        ),
        0,
      );
      expect(
        projectQuickSwitchIndexAtY(
          localY: extent,
          itemExtent: extent,
          length: 5,
        ),
        1,
      );
      expect(
        projectQuickSwitchIndexAtY(
          localY: extent * 2.5,
          itemExtent: extent,
          length: 5,
        ),
        2,
      );
    });

    test('面板被顶到上边界后按压点仍映射到视觉行（修复偏一项）', () {
      // 模拟：按压 y=50、startIndex=1、panelPadding=8、itemExtent=44
      // 理想 top=50-8-1.5*44=-24 → clamp 到 8
      // 内容顶 = panelTop + padding = 16
      // 按压点 localY = 50 - 16 = 34 → 应落在第 0 行，而非相对位移仍停在 startIndex=1
      const panelTop = 8.0;
      const panelPaddingV = 8.0;
      const pressY = 50.0;
      const itemExtent = 44.0;
      final localY = pressY - panelTop - panelPaddingV;
      expect(localY, 34);
      expect(
        projectQuickSwitchIndexAtY(
          localY: localY,
          itemExtent: itemExtent,
          length: 4,
        ),
        0,
      );
      // 指针移到第 1 行中心（视觉）时应高亮 1
      final row1CenterGlobal =
          panelTop + panelPaddingV + (1 + 0.5) * itemExtent;
      expect(
        projectQuickSwitchIndexAtY(
          localY: row1CenterGlobal - panelTop - panelPaddingV,
          itemExtent: itemExtent,
          length: 4,
        ),
        1,
      );
    });

    test('夹紧边界', () {
      expect(
        projectQuickSwitchIndexAtY(
          localY: -20,
          itemExtent: 44,
          length: 3,
        ),
        0,
      );
      expect(
        projectQuickSwitchIndexAtY(
          localY: 999,
          itemExtent: 44,
          length: 3,
        ),
        2,
      );
    });
  });
}
