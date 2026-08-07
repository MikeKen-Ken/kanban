import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/main.dart';
import 'package:kanban/webdav_sync/webdav_sync_service.dart';

void main() {
  test('同步状态展示上次成功同步时间', () {
    final time = DateTime(2026, 8, 3, 17, 5);
    expect(formatSyncTime(time), '08-03 17:05');
    expect(
      syncStatusWithLastSuccessLabel(SyncStatus.success, time),
      '已同步 08-03 17:05',
    );
    expect(
      syncStatusWithLastSuccessLabel(SyncStatus.syncing, time),
      '同步中…',
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
    expect(progress.shortLabel, '同步中 3/12');
    expect(
      syncStatusWithLastSuccessLabel(
        SyncStatus.syncing,
        DateTime(2026, 8, 3, 17, 5),
        progress: progress,
      ),
      '同步中 3/12',
    );
  });
}
