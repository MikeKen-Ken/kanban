import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'backup_history_store.dart';

BackupHistoryStore createBackupHistoryStore({Object? baseDirectory}) =>
    _IoBackupHistoryStore(baseDirectory as Directory?);

class _IoBackupHistoryStore implements BackupHistoryStore {
  _IoBackupHistoryStore(this._baseDirectory);

  static const _extension = '.kanban-backup';
  final Directory? _baseDirectory;

  @override
  bool get isSupported => true;

  Future<Directory> _directory() async {
    final base =
        _baseDirectory ?? await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(base.path, 'kanban', 'backups'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  @override
  Future<BackupSnapshotInfo> save(
    Uint8List bytes, {
    required DateTime createdAt,
  }) async {
    final directory = await _directory();
    final id =
        '${createdAt.toUtc().millisecondsSinceEpoch}-${const Uuid().v4()}';
    final file = File(p.join(directory.path, '$id$_extension'));
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
    return BackupSnapshotInfo(
      id: id,
      createdAt: createdAt.toUtc(),
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<List<BackupSnapshotInfo>> list() async {
    final directory = await _directory();
    final snapshots = <BackupSnapshotInfo>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith(_extension)) continue;
      final name = p.basenameWithoutExtension(entity.path);
      final timestamp = int.tryParse(name.split('-').first);
      if (timestamp == null) continue;
      snapshots.add(
        BackupSnapshotInfo(
          id: name,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            timestamp,
            isUtc: true,
          ),
          sizeBytes: await entity.length(),
        ),
      );
    }
    snapshots.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return snapshots;
  }

  @override
  Future<Uint8List?> read(String id) async {
    final file = await _fileForId(id);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> deleteOlderThan(DateTime cutoff) async {
    final cutoffUtc = cutoff.toUtc();
    for (final snapshot in await list()) {
      if (!snapshot.createdAt.isBefore(cutoffUtc)) continue;
      await delete(snapshot.id);
    }
  }

  @override
  Future<void> delete(String id) async {
    final file = await _fileForId(id);
    if (await file.exists()) await file.delete();
  }

  Future<File> _fileForId(String id) async {
    if (id.isEmpty ||
        id.contains('/') ||
        id.contains('\\') ||
        id.contains('..')) {
      throw const FormatException('备份标识无效');
    }
    final directory = await _directory();
    return File(p.join(directory.path, '$id$_extension'));
  }
}
