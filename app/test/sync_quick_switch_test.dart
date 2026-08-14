import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/webdav_sync/sync_actions_sheet.dart';
import 'package:kanban/webdav_sync/sync_quick_switch.dart';

void main() {
  group('SyncQuickSwitchGesture 取消', () {
    Future<void> pumpSwitcher(
      WidgetTester tester, {
      required List<SyncManualAction> committed,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                SyncQuickSwitchGesture(
                  longPressDelay: const Duration(milliseconds: 50),
                  onCommit: (action) async {
                    committed.add(action);
                  },
                  child: const Text('同步'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Future<TestGesture> startQuickSwitch(WidgetTester tester) async {
      final center = tester.getCenter(find.text('同步'));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      return gesture;
    }

    testWidgets('长按后不滑动松手落在取消，不提交同步', (tester) async {
      final committed = <SyncManualAction>[];
      await pumpSwitcher(tester, committed: committed);

      final gesture = await startQuickSwitch(tester);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('上传'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(committed, isEmpty);
      expect(find.text('取消'), findsNothing);
    });

    testWidgets('从取消下滑到上传后松手才提交', (tester) async {
      final committed = <SyncManualAction>[];
      await pumpSwitcher(tester, committed: committed);

      final gesture = await startQuickSwitch(tester);
      expect(find.text('取消'), findsOneWidget);

      await gesture.moveBy(
        Offset(0, SyncQuickSwitchGesture.itemExtent),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(committed, [SyncManualAction.upload]);
    });
  });
}
