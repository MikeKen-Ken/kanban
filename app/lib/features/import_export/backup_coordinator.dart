import 'dart:async';
import 'dart:typed_data';

import '../../common/async_mutex.dart';
import 'backup_history_store.dart';

typedef BackupArchiveFactory = Future<Uint8List> Function();
typedef RemoteBackupWriter = Future<void> Function(
  BackupSnapshotInfo snapshot,
  Uint8List bytes,
);
typedef RemoteBackupLister = Future<List<BackupSnapshotInfo>> Function();
typedef RemoteBackupPruner = Future<void> Function(DateTime cutoff);

/// 协调自动与手动时间点备份，并执行本地、远端保留策略。
class BackupCoordinator {
  BackupCoordinator({
    required BackupHistoryStore localStore,
    required BackupArchiveFactory createArchive,
    RemoteBackupWriter? writeRemote,
    RemoteBackupLister? listRemote,
    RemoteBackupPruner? pruneRemote,
    DateTime Function()? now,
    this.interval = const Duration(minutes: 10),
    this.retention = const Duration(days: 7),
  })  : _localStore = localStore,
        _createArchive = createArchive,
        _writeRemote = writeRemote,
        _listRemote = listRemote,
        _pruneRemote = pruneRemote,
        _now = now ?? DateTime.now;

  final BackupHistoryStore _localStore;
  final BackupArchiveFactory _createArchive;
  final RemoteBackupWriter? _writeRemote;
  final RemoteBackupLister? _listRemote;
  final RemoteBackupPruner? _pruneRemote;
  final DateTime Function() _now;
  final AsyncMutex _mutex = AsyncMutex();
  final AsyncMutex _remoteMutex = AsyncMutex();
  final Map<String, BackupSnapshotInfo> _pendingRemote = {};

  final Duration interval;
  final Duration retention;

  Timer? _timer;
  int _changeVersion = 0;
  int _backedUpVersion = 0;
  DateTime? _lastBackupAt;
  bool _remoteMaintenanceRunning = false;
  bool _remoteMaintenanceRequested = false;
  DateTime? _remoteMaintenanceTime;

  void markChanged() {
    _changeVersion++;
  }

  void start() {
    if (_timer != null) return;
    _armTimer();
    unawaited(runScheduledBackup());
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      unawaited(runScheduledBackup());
    });
  }

  Future<BackupSnapshotInfo?> runScheduledBackup() {
    return _mutex.guard(() async {
      final now = _now();
      final last = _lastBackupAt;
      if (_changeVersion == _backedUpVersion ||
          (last != null && now.difference(last) < interval)) {
        await _pruneLocal(now);
        _scheduleRemoteMaintenance(now);
        return null;
      }
      return _createAndStore(now);
    });
  }

  Future<BackupSnapshotInfo> createBackupNow() {
    return _mutex.guard(() => _createAndStore(_now()));
  }

  Future<BackupSnapshotInfo> storeArchiveNow(Uint8List bytes) {
    return _mutex.guard(
      () => _storeArchive(
        bytes,
        createdAt: _now(),
        capturedVersion: _changeVersion,
      ),
    );
  }

  Future<T> runExclusive<T>(Future<T> Function() action) =>
      _mutex.guard(action);

  Future<List<BackupSnapshotInfo>> listLocalBackups() => _localStore.list();

  Future<Uint8List?> readLocalBackup(String id) => _localStore.read(id);

  Future<void> deleteLocalBackup(String id) => _localStore.delete(id);

  Future<BackupSnapshotInfo> _createAndStore(DateTime createdAt) async {
    final capturedVersion = _changeVersion;
    final bytes = await _createArchive();
    return _storeArchive(
      bytes,
      createdAt: createdAt,
      capturedVersion: capturedVersion,
    );
  }

  Future<BackupSnapshotInfo> _storeArchive(
    Uint8List bytes, {
    required DateTime createdAt,
    required int capturedVersion,
  }) async {
    final snapshot = await _localStore.save(bytes, createdAt: createdAt);
    _lastBackupAt = createdAt;
    if (capturedVersion > _backedUpVersion) {
      _backedUpVersion = capturedVersion;
    }
    if (_timer != null) _armTimer();
    _pendingRemote[snapshot.id] = snapshot;
    await _pruneLocal(createdAt);
    _scheduleRemoteMaintenance(createdAt);
    return snapshot;
  }

  Future<void> _writeRemoteOrQueue(
    BackupSnapshotInfo snapshot,
    Uint8List bytes,
  ) async {
    final writeRemote = _writeRemote;
    if (writeRemote == null) return;
    try {
      await writeRemote(snapshot, bytes);
      _pendingRemote.remove(snapshot.id);
    } catch (_) {
      // 本地还原点已经成功，远端失败留待下个周期重试。
      _pendingRemote[snapshot.id] = snapshot;
    }
  }

  Future<void> _flushPendingRemote() async {
    final writeRemote = _writeRemote;
    if (writeRemote == null || _pendingRemote.isEmpty) return;
    for (final snapshot in _pendingRemote.values.toList()) {
      final bytes = await _localStore.read(snapshot.id);
      if (bytes == null) {
        _pendingRemote.remove(snapshot.id);
        continue;
      }
      await _writeRemoteOrQueue(snapshot, bytes);
    }
  }

  Future<void> _mirrorMissingLocalBackups() async {
    final listRemote = _listRemote;
    final writeRemote = _writeRemote;
    if (listRemote == null || writeRemote == null) return;
    try {
      final remoteIds =
          (await listRemote()).map((snapshot) => snapshot.id).toSet();
      for (final snapshot in await _localStore.list()) {
        if (remoteIds.contains(snapshot.id)) continue;
        final bytes = await _localStore.read(snapshot.id);
        if (bytes == null) continue;
        await _writeRemoteOrQueue(snapshot, bytes);
      }
    } catch (_) {
      // WebDAV 不可用时保留本地备份，下个周期再次镜像。
    }
  }

  Future<void> _pruneLocal(DateTime now) async {
    final cutoff = now.subtract(retention);
    await _localStore.deleteOlderThan(cutoff);
    _pendingRemote.removeWhere(
      (_, snapshot) => snapshot.createdAt.isBefore(cutoff),
    );
  }

  void _scheduleRemoteMaintenance(DateTime now) {
    _remoteMaintenanceTime = now;
    _remoteMaintenanceRequested = true;
    if (_remoteMaintenanceRunning) return;
    _remoteMaintenanceRunning = true;
    unawaited(_runRemoteMaintenance());
  }

  Future<void> _runRemoteMaintenance() async {
    try {
      await _remoteMutex.guard(() async {
        do {
          _remoteMaintenanceRequested = false;
          final now = _remoteMaintenanceTime ?? _now();
          await _flushPendingRemote();
          await _mirrorMissingLocalBackups();
          await _pruneRemoteBackups(now);
        } while (_remoteMaintenanceRequested);
      });
    } finally {
      _remoteMaintenanceRunning = false;
      if (_remoteMaintenanceRequested) {
        _scheduleRemoteMaintenance(_remoteMaintenanceTime ?? _now());
      }
    }
  }

  Future<void> _pruneRemoteBackups(DateTime now) async {
    final cutoff = now.subtract(retention);
    final pruneRemote = _pruneRemote;
    if (pruneRemote != null) {
      try {
        await pruneRemote(cutoff);
      } catch (_) {
        // 远端清理失败不会删除本地还原点，下个周期继续尝试。
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
