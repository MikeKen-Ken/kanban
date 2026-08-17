import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/screens/settings_screen.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_settings_ui_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
  });

  tearDown(() async {
    controller.dispose();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } on PathAccessException {
      // Windows 偶发文件占用，不影响断言结果。
    }
  });

  testWidgets('设置首页只显示当前项目一级入口，点进去才出现项目设置和活动历史',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前项目'), findsOneWidget);
    expect(find.text('项目设置'), findsNothing);
    expect(find.text('活动历史'), findsNothing);
    expect(find.text('拖拽按压时长'), findsNothing);
    expect(find.text('导出完整备份'), findsNothing);

    await tester.tap(find.text('当前项目'));
    await tester.pumpAndSettle();

    expect(find.text('项目设置'), findsOneWidget);
    expect(find.text('活动历史'), findsOneWidget);
  });
}
