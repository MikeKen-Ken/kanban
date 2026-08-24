import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/main.dart';
import 'package:kanban/webdav_sync/webdav_sync_service.dart';

void main() {
  test('同步状态展示上次成功同步时间', () {
    final time = DateTime(2026, 8, 3, 17, 5);
    expect(formatSyncTime(time), '08-03 17:05');
    expect(
      syncStatusWithLastSuccessLabel(SyncStatus.success, time),
      'Synced 08-03 17:05',
    );
    expect(
      syncStatusWithLastSuccessLabel(SyncStatus.syncing, time),
      'Syncing…',
    );
  });

  test('已同步后追加待同步数量，为 0 时不展示', () {
    final time = DateTime(2026, 8, 3, 17, 5);
    expect(
      syncStatusWithLastSuccessLabel(
        SyncStatus.success,
        time,
        pendingUploadCount: 0,
      ),
      'Synced 08-03 17:05',
    );
    expect(
      syncStatusWithLastSuccessLabel(
        SyncStatus.success,
        time,
        pendingUploadCount: 4,
      ),
      'Synced 08-03 17:05 · 4 pending',
    );
    expect(
      syncStatusWithLastSuccessLabel(
        SyncStatus.idle,
        time,
        pendingUploadCount: 2,
      ),
      'Synced 08-03 17:05 · 2 pending',
    );
  });

  test('同步中展示文件进度计数', () {
    const progress = SyncProgress(
      phase: SyncPhase.uploading,
      completed: 3,
      total: 12,
      skipped: 5,
      currentLabel: '甲 / 待办',
    );
    expect(progress.shortLabel, 'Syncing 3/12');
    expect(
      syncStatusWithLastSuccessLabel(
        SyncStatus.syncing,
        DateTime(2026, 8, 3, 17, 5),
        progress: progress,
        pendingUploadCount: 9,
      ),
      'Syncing 3/12',
    );
  });

  test('窄屏同步摘要保留状态与最近同步日期', () {
    final time = DateTime(2026, 8, 3, 17, 5);
    expect(
      compactSyncStatusLabel(SyncStatus.success, time),
      'Synced 08-03',
    );
    expect(
      compactSyncStatusLabel(
        SyncStatus.idle,
        time,
        pendingUploadCount: 4,
      ),
      '4 pending · 08-03',
    );
    expect(
      compactSyncStatusLabel(SyncStatus.error, time),
      'Sync failed · 08-03',
    );
  });
}
