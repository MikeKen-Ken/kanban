import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/import_export/backup_coordinator.dart';
import 'package:kanban/features/import_export/backup_history_store.dart';

void main() {
  test('只有数据更新且间隔达到十分钟时才创建自动备份', () async {
    final store = _MemoryBackupHistoryStore();
    var now = DateTime.utc(2026, 8, 6, 12);
    var archiveCount = 0;
    final coordinator = BackupCoordinator(
      localStore: store,
      createArchive: () async {
        archiveCount++;
        return Uint8List.fromList([archiveCount]);
      },
      now: () => now,
    );

    coordinator.markChanged();
    expect(await coordinator.runScheduledBackup(), isNotNull);
    expect(archiveCount, 1);

    coordinator.markChanged();
    now = now.add(const Duration(minutes: 9));
    expect(await coordinator.runScheduledBackup(), isNull);
    expect(archiveCount, 1);

    now = now.add(const Duration(minutes: 1));
    expect(await coordinator.runScheduledBackup(), isNotNull);
    expect(archiveCount, 2);

    now = now.add(const Duration(minutes: 10));
    expect(await coordinator.runScheduledBackup(), isNull);
    expect(archiveCount, 2);
  });

  test('手动备份不需要等待十分钟', () async {
    final store = _MemoryBackupHistoryStore();
    final coordinator = BackupCoordinator(
      localStore: store,
      createArchive: () async => Uint8List.fromList([7]),
      now: () => DateTime.utc(2026, 8, 6),
    );

    final snapshot = await coordinator.createBackupNow();

    expect(snapshot.sizeBytes, 1);
    expect(await store.read(snapshot.id), [7]);
  });

  test('归档生成期间的新修改不会被旧备份清除', () async {
    final store = _MemoryBackupHistoryStore();
    final entered = Completer<void>();
    final release = Completer<void>();
    var now = DateTime.utc(2026, 8, 6, 12);
    var archiveCount = 0;
    final coordinator = BackupCoordinator(
      localStore: store,
      createArchive: () async {
        archiveCount++;
        if (archiveCount == 1) {
          entered.complete();
          await release.future;
        }
        return Uint8List.fromList([archiveCount]);
      },
      now: () => now,
    );

    coordinator.markChanged();
    final first = coordinator.runScheduledBackup();
    await entered.future;
    coordinator.markChanged();
    release.complete();
    await first;

    now = now.add(const Duration(minutes: 10));
    expect(await coordinator.runScheduledBackup(), isNotNull);
    expect(archiveCount, 2);
  });
}

class _MemoryBackupHistoryStore implements BackupHistoryStore {
  final Map<String, Uint8List> _bytes = {};
  final Map<String, BackupSnapshotInfo> _items = {};
  int _sequence = 0;

  @override
  bool get isSupported => true;

  @override
  Future<BackupSnapshotInfo> save(
    Uint8List bytes, {
    required DateTime createdAt,
  }) async {
    final id = '${createdAt.millisecondsSinceEpoch}-${_sequence++}';
    final info = BackupSnapshotInfo(
      id: id,
      createdAt: createdAt,
      sizeBytes: bytes.length,
    );
    _bytes[id] = bytes;
    _items[id] = info;
    return info;
  }

  @override
  Future<List<BackupSnapshotInfo>> list() async {
    final result = _items.values.toList();
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Future<Uint8List?> read(String id) async => _bytes[id];

  @override
  Future<void> deleteOlderThan(DateTime cutoff) async {
    final expired = _items.values
        .where((item) => item.createdAt.isBefore(cutoff))
        .map((item) => item.id)
        .toList();
    for (final id in expired) {
      await delete(id);
    }
  }

  @override
  Future<void> delete(String id) async {
    _items.remove(id);
    _bytes.remove(id);
  }
}
