import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'controllers/board_controller.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/project/project_theme.dart';
import 'screens/home_screen.dart';
import 'utils/windows_clipboard_history_paste.dart';
import 'webdav_sync/webdav_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 卡片/详情里的 DateFormat.*('zh_CN') 依赖 locale 数据；未初始化会变成超高 ErrorWidget
  await initializeDateFormatting('zh_CN');
  final controller = await BoardController.create();
  // 先初始化渠道与调度；权限申请需等 Activity 就绪后再做
  await controller.initializeReminders();
  runApp(KanbanApp(controller: controller));
  // 修复 Windows Win+V 剪贴板历史无法粘贴到输入框（flutter#143997）
  installWindowsClipboardHistoryPasteFix();
}

class KanbanApp extends StatefulWidget {
  const KanbanApp({super.key, required this.controller});

  final BoardController controller;

  @override
  State<KanbanApp> createState() => _KanbanAppState();
}

class _KanbanAppState extends State<KanbanApp> {
  @override
  void initState() {
    super.initState();
    // Activity 就绪后首次申请通知权限（Android 13+）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.controller.ensureNotificationPermissionOnFirstLaunch());
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.controller,
      child: Consumer<BoardController>(
        builder: (context, boardController, _) {
          final preset =
              projectThemeForId(boardController.projectSettings.themeId);
          return MaterialApp(
            title: '看板',
            debugShowCheckedModeBanner: false,
            theme: buildKanbanTheme(preset, Brightness.light),
            darkTheme: buildKanbanTheme(preset, Brightness.dark),
            themeMode: boardController.appSettings.themeMode,
            locale: const Locale('zh', 'CN'),
            home: boardController.appSettings.hasCompletedOnboarding
                ? const HomeScreen()
                : OnboardingScreen(
                    onCompleted: () => boardController.saveAppSettings(
                      boardController.appSettings.copyWith(
                        hasCompletedOnboarding: true,
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

String syncStatusLabel(SyncStatus status) {
  switch (status) {
    case SyncStatus.idle:
      return '待命';
    case SyncStatus.syncing:
      return '同步中…';
    case SyncStatus.success:
      return '已同步';
    case SyncStatus.error:
      return '同步失败';
  }
}

String formatSyncTime(DateTime time) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${twoDigits(time.month)}-${twoDigits(time.day)} '
      '${twoDigits(time.hour)}:${twoDigits(time.minute)}';
}

String syncStatusWithLastSuccessLabel(
  SyncStatus status,
  DateTime? lastSyncedAt,
) {
  if (lastSyncedAt == null || status == SyncStatus.syncing) {
    return syncStatusLabel(status);
  }
  if (status == SyncStatus.error) {
    return syncStatusLabel(status);
  }
  return '已同步 ${formatSyncTime(lastSyncedAt)}';
}

IconData syncStatusIcon(SyncStatus status) {
  switch (status) {
    case SyncStatus.idle:
      return Icons.cloud_outlined;
    case SyncStatus.syncing:
      return Icons.cloud_sync_outlined;
    case SyncStatus.success:
      return Icons.cloud_done_outlined;
    case SyncStatus.error:
      return Icons.cloud_off_outlined;
  }
}
