import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/import_export/backup_history_store.dart';

void main() {
  test('本地备份历史可以保存、读取并按一周保留期清理', () async {
    final dir = await Directory.systemTemp.createTemp('kanban_backups_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = BackupHistoryStore(baseDirectory: dir);
    final now = DateTime.utc(2026, 8, 6, 12);
    final old = await store.save(
      Uint8List.fromList([1, 2, 3]),
      createdAt: now.subtract(const Duration(days: 8)),
    );
    final current = await store.save(
      Uint8List.fromList([4, 5, 6]),
      createdAt: now,
    );

    expect(await store.read(current.id), [4, 5, 6]);
    expect((await store.list()).map((item) => item.id), [current.id, old.id]);

    await store.deleteOlderThan(now.subtract(const Duration(days: 7)));

    expect((await store.list()).map((item) => item.id), [current.id]);
    expect(await store.read(old.id), isNull);
  });
}
