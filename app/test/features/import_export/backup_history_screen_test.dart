import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/import_export/backup_history_screen.dart';
import 'package:kanban/features/import_export/backup_history_store.dart';

void main() {
  testWidgets('仅展示本地备份，不会等待远端备份列表', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackupHistoryScreen(
          listLocalBackups: () async => const [],
          autoBackupDirectory: () => null,
          autoBackupRetentionDays: () => 14,
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('backup-history-loading')), findsOneWidget);

    await tester.pump();
    await tester.pump();

    expect(
        find.byKey(const ValueKey('backup-history-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('local-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-history-loading')), findsNothing);
    expect(find.text('WebDAV 备份'), findsNothing);
  });

  testWidgets('有本地备份时展示列表项', (tester) async {
    final snapshot = BackupSnapshotInfo(
      id: '1000-abcd',
      createdAt: DateTime.utc(2026, 8, 6, 12),
      sizeBytes: 2048,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BackupHistoryScreen(
          listLocalBackups: () async => [snapshot],
          autoBackupDirectory: () => null,
          autoBackupRetentionDays: () => 14,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('local-empty')), findsNothing);
    expect(find.textContaining('2026-08-06'), findsOneWidget);
  });

  testWidgets('本地失败时展示错误文案并结束 loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackupHistoryScreen(
          listLocalBackups: () async => throw StateError('磁盘不可用'),
          autoBackupDirectory: () => null,
          autoBackupRetentionDays: () => 14,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
        find.byKey(const ValueKey('backup-history-content')), findsOneWidget);
    expect(find.textContaining('Could not read local backups'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-history-loading')), findsNothing);
  });
}
