import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kanban/features/project/project_quick_switch.dart';
import 'package:kanban/features/project/projects_manifest.dart';

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

  group('ProjectQuickSwitchGesture 窗口边界', () {
    List<ProjectEntry> projects() => [
          const ProjectEntry(
            id: 'a',
            title: '项目甲',
            updatedAt: 1,
            revision: 1,
          ),
          const ProjectEntry(
            id: 'b',
            title: '项目乙',
            updatedAt: 2,
            revision: 1,
          ),
          const ProjectEntry(
            id: 'c',
            title: '项目丙',
            updatedAt: 3,
            revision: 1,
          ),
        ];

    testWidgets('PointerCancel 后面板仍在，新 pointer 按住移动可继续切换',
        (tester) async {
      String? committed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: ProjectQuickSwitchGesture(
                projects: projects(),
                activeProjectId: 'a',
                longPressDelay: const Duration(milliseconds: 50),
                themeIdFor: (_) => 'default',
                onCommit: (id) async {
                  committed = id;
                },
                child: const Text('当前项目'),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.text('当前项目'));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      // 已进入快速切换：面板列出各项目
      expect(find.text('项目甲'), findsWidgets);
      expect(find.text('项目乙'), findsOneWidget);

      // 模拟移出窗口：cancel 原 pointer（不松键）
      await gesture.cancel();
      await tester.pump();

      // 会话应保持：面板仍在
      expect(find.text('项目乙'), findsOneWidget);
      expect(committed, isNull);

      // 再次进入：新 pointer 按住并下移到更靠下的位置
      final resumed = await tester.startGesture(
        center.translate(0, 96),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await resumed.moveBy(const Offset(0, 20));
      await tester.pump();

      // 仍可跟手：面板未因 cancel 关闭
      expect(find.text('项目丙'), findsOneWidget);

      await resumed.up();
      await tester.pumpAndSettle();

      // 松手应提交（高亮项可能是乙或丙，取决于绝对 Y；关键是流程能走完）
      expect(committed, isNotNull);
      expect(find.text('项目乙'), findsNothing);
    });
  });
}
