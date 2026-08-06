import 'dart:typed_data';

import 'backup_history_store.dart';

BackupHistoryStore createBackupHistoryStore({Object? baseDirectory}) =>
    _UnsupportedBackupHistoryStore();

class _UnsupportedBackupHistoryStore implements BackupHistoryStore {
  Never _unsupported() =>
      throw UnsupportedError('当前平台暂不支持本地备份历史');

  @override
  bool get isSupported => false;

  @override
  Future<void> delete(String id) async => _unsupported();

  @override
  Future<void> deleteOlderThan(DateTime cutoff) async => _unsupported();

  @override
  Future<List<BackupSnapshotInfo>> list() async => _unsupported();

  @override
  Future<Uint8List?> read(String id) async => _unsupported();

  @override
  Future<BackupSnapshotInfo> save(
    Uint8List bytes, {
    required DateTime createdAt,
  }) async =>
      _unsupported();
}
