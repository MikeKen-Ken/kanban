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

    expect(find.text('Current project'), findsOneWidget);
    expect(find.text('Project settings'), findsNothing);
    expect(find.text('Activity history'), findsNothing);
    expect(find.text('Drag press duration'), findsNothing);
    expect(find.text('Export full backup'), findsNothing);

    await tester.tap(find.text('Current project'));
    await tester.pumpAndSettle();

    expect(find.text('Project settings'), findsOneWidget);
    expect(find.text('Activity history'), findsOneWidget);
  });
}
