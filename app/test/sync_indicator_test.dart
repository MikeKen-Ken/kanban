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
}
