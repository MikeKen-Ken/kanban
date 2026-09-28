import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/kanban/card_detail_actions_bar.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_actions_bar_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
  });

  tearDown(() async {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows can keep the temp directory locked for a moment after dispose.
    }
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    required Size size,
    required bool showComplete,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: CardDetailActionsBar(
              columnId: 'todo',
              cardId: 'card',
              cardTitle: 'Card title',
              showComplete: showComplete,
              onSaveAsTemplate: () {},
              onTransfer: () {},
              onDeleted: () {},
              onComplete: () async {},
              onSave: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectFullyInside(Rect inner, Rect outer) {
    expect(inner.left, greaterThanOrEqualTo(outer.left - 0.5));
    expect(inner.right, lessThanOrEqualTo(outer.right + 0.5));
    expect(inner.top, greaterThanOrEqualTo(outer.top - 0.5));
    expect(inner.bottom, lessThanOrEqualTo(outer.bottom + 0.5));
  }

  testWidgets('窄屏底栏换行，Delete 不再被 Save 裁切', (tester) async {
    await pumpBar(
      tester,
      size: const Size(360, 800),
      showComplete: false,
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(Wrap), findsOneWidget);

    final bar = tester.getRect(find.byType(CardDetailActionsBar));
    final deleteRect = tester.getRect(find.text('Delete'));
    final saveButton =
        tester.getRect(find.widgetWithText(FilledButton, 'Save'));
    expectFullyInside(deleteRect, bar);
    expectFullyInside(saveButton, bar);
    expect(deleteRect.overlaps(saveButton), isFalse);
    expect(deleteRect.right, lessThanOrEqualTo(saveButton.left));
    expect(saveButton.right, closeTo(bar.right - 12, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏同时显示完成时按钮仍完整可见', (tester) async {
    await pumpBar(
      tester,
      size: const Size(360, 800),
      showComplete: true,
    );

    final bar = tester.getRect(find.byType(CardDetailActionsBar));
    for (final label in const ['Delete', 'Complete', 'Save']) {
      expectFullyInside(tester.getRect(find.text(label)), bar);
    }
    final saveButton =
        tester.getRect(find.widgetWithText(FilledButton, 'Save'));
    expect(saveButton.right, closeTo(bar.right - 12, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏底栏保持单行', (tester) async {
    await pumpBar(
      tester,
      size: const Size(800, 600),
      showComplete: false,
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);
    final bar = tester.getRect(find.byType(CardDetailActionsBar));
    final deleteRect = tester.getRect(find.text('Delete'));
    final saveButton =
        tester.getRect(find.widgetWithText(FilledButton, 'Save'));
    expect(deleteRect.overlaps(saveButton), isFalse);
    expect(saveButton.right, closeTo(bar.right - 12, 1));
    expect(tester.takeException(), isNull);
  });
}
