import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:kanban/widgets/kanban_column_widget.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_empty_col_');
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

  testWidgets('空列在 PageView 式紧宽度约束下仍按内容收缩', (tester) async {
    final target = controller.board!.columns.first;
    for (final card in List.of(target.cards)) {
      await controller.deleteCard(target.id, card.id);
    }
    final column =
        controller.board!.columns.firstWhere((c) => c.id == target.id);
    expect(column.cards, isEmpty);

    const tightWidth = 360.0;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: tightWidth,
                height: 640,
                child: KanbanColumnWidget(
                  column: column,
                  columnIndex: 0,
                  width: tightWidth,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bodyColumn = find
        .descendant(
          of: find.byType(KanbanColumnWidget),
          matching: find.byType(Column),
        )
        .first;
    final width = tester.getSize(bodyColumn).width;
    expect(width, lessThan(tightWidth - 40));
    expect(width, greaterThan(80));

    // 卸掉界面，避免 tearDown 删目录时文件仍被占用。
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
