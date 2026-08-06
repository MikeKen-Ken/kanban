import 'dart:typed_data';

import 'backup_history_store_stub.dart'
    if (dart.library.io) 'backup_history_store_io.dart';

class BackupSnapshotInfo {
  const BackupSnapshotInfo({
    required this.id,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String id;
  final DateTime createdAt;
  final int sizeBytes;
}

/// 本机工作区时间点备份存储。
abstract class BackupHistoryStore {
  factory BackupHistoryStore({Object? baseDirectory}) =>
      createBackupHistoryStore(baseDirectory: baseDirectory);

  bool get isSupported;

  Future<BackupSnapshotInfo> save(
    Uint8List bytes, {
    required DateTime createdAt,
  });

  Future<List<BackupSnapshotInfo>> list();

  Future<Uint8List?> read(String id);

  Future<void> deleteOlderThan(DateTime cutoff);

  Future<void> delete(String id);
}
