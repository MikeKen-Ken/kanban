import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/import_export/backup_history_store.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('可以将整个工作区恢复到指定时间点', () async {
    final dataDir = await Directory.systemTemp.createTemp('kanban_data_');
    final backupDir =
        await Directory.systemTemp.createTemp('kanban_backup_timeline_');
    addTearDown(() async {
      if (await dataDir.exists()) await dataDir.delete(recursive: true);
      if (await backupDir.exists()) await backupDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = BoardStorage(baseDirectory: dataDir, prefs: prefs);
    final controller = await BoardController.createForTest(
      prefs: prefs,
      storage: storage,
      backupHistoryStore: BackupHistoryStore(baseDirectory: backupDir),
    );
    addTearDown(controller.dispose);

    await controller.addCard('todo', '时间点内');
    final snapshot = await controller.createTimePointBackup();
    await controller.addCard('todo', '时间点后');
    final laterProject = await controller.createProjectData('时间点后项目');

    await controller.restoreTimePointBackup(snapshot.id);

    final titles = controller.board!.columns
        .expand((column) => column.cards)
        .map((card) => card.title)
        .toSet();
    expect(titles, contains('时间点内'));
    expect(titles, isNot(contains('时间点后')));
    expect(controller.projects.any((project) => project.id == laterProject), isFalse);
    expect(await storage.hasProjectBoard(laterProject), isFalse);
    expect((await controller.listLocalTimePointBackups()).length, greaterThan(1));
  });
}
