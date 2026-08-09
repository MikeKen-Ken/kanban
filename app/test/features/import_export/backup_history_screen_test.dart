import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/import_export/backup_history_screen.dart';
import 'package:kanban/features/import_export/backup_history_store.dart';

void main() {
  testWidgets('远端挂起时仍展示本地空状态，不再永久整页转圈', (tester) async {
    final remoteGate = Completer<List<BackupSnapshotInfo>>();

    await tester.pumpWidget(
      MaterialApp(
        home: BackupHistoryScreen(
          listLocalBackups: () async => const [],
          listRemoteBackups: () => remoteGate.future,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('backup-history-loading')), findsOneWidget);

    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('backup-history-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('local-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-history-loading')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    remoteGate.complete(const []);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('remote-empty')), findsOneWidget);
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
          listRemoteBackups: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('local-empty')), findsNothing);
    expect(find.textContaining('2026-08-06'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-empty')), findsOneWidget);
  });

  testWidgets('本地失败时展示错误文案并结束 loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackupHistoryScreen(
          listLocalBackups: () async => throw StateError('磁盘不可用'),
          listRemoteBackups: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('backup-history-content')), findsOneWidget);
    expect(find.textContaining('本地备份无法读取'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-history-loading')), findsNothing);
  });

  testWidgets('远端超时时展示可见错误提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackupHistoryScreen(
          listLocalBackups: () async => const [],
          listRemoteBackups: () => Completer<List<BackupSnapshotInfo>>().future,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('backup-history-content')), findsOneWidget);

    await tester.pump(kRemoteBackupListTimeout + const Duration(seconds: 1));

    expect(find.textContaining('WebDAV 备份读取超时'), findsOneWidget);
  });
}
