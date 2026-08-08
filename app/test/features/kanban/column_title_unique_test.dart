import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_col_unique_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('addColumn 拒绝同名列', () async {
    final err = await controller.addColumn('待返工');
    expect(err, contains('已存在同名列'));
    expect(
      controller.board!.columns
          .where((c) => c.title == KanbanBoard.defaultReworkColumnTitle)
          .length,
      1,
    );
  });

  test('renameColumn 拒绝改成已有列名', () async {
    final err = await controller.renameColumn('todo', '进行中');
    expect(err, contains('已存在同名列'));
    expect(
      controller.board!.columns.firstWhere((c) => c.id == 'todo').title,
      '待办',
    );
  });

  test('ensureRework 后再 addColumn 待返工仍失败', () async {
    await controller.ensureReworkColumn();
    final err = await controller.addColumn('待返工');
    expect(err, isNotNull);
    expect(
      controller.board!.columns.where((c) => c.title == '待返工').length,
      1,
    );
  });
}
