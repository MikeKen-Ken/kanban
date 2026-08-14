import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'controllers/board_controller.dart';
import 'features/kanban/card_complete_motion.dart';
import 'features/agent_dispatch/agent_dispatch_after_queue.dart';
import 'features/agent_dispatch/agent_dispatch_registry.dart';
import 'features/agent_dispatch/agent_dispatch_window.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/project/project_theme.dart';
import 'screens/home_screen.dart';
import 'utils/windows_clipboard_history_paste.dart';
import 'webdav_sync/webdav_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 取消可能残留的延时关机，避免开机后立刻休眠。
  unawaited(abortStaleWindowsPowerAction());
  // 卡片/详情里的 DateFormat.*('zh_CN') 依赖 locale 数据；未初始化会变成超高 ErrorWidget
  await initializeDateFormatting('zh_CN');
  final controller = await BoardController.create();
  // 先出首帧再初始化提醒：Windows 上通知插件在 runApp 前 await 会挂起，窗口永不 Show
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

class _KanbanAppState extends State<KanbanApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

  void _dismissWithEscape() {
    if (AgentDispatchWindow.hideIfVisible()) return;
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    final isEditingText = focusedContext?.widget is EditableText ||
        focusedContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (isEditingText) return;
    unawaited(_navigatorKey.currentState?.maybePop());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧后再初始化通知插件并申请权限，避免阻塞窗口显示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.controller.initializeReminders());
      unawaited(widget.controller.ensureNotificationPermissionOnFirstLaunch());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Dart 仍可执行清理时，主动结束 Agent Worker 及其子进程。
    unawaited(AgentDispatchRegistry.instance.stopAll());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(AgentDispatchRegistry.instance.stopAll());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.purgeExpiredCompletedCards());
      unawaited(widget.controller.purgeExpiredTrashItems());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.controller),
        ChangeNotifierProvider(create: (_) => CardCompleteFlightController()),
      ],
      // 仅主题/引导相关字段变化时重建 MaterialApp，避免每次改卡都重建整棵应用树
      //（详情弹层在冲突解决 notify 时曾因此出现“点了没反应”的体感）。
      child: Selector<BoardController,
          ({String themeId, ThemeMode themeMode, bool onboardingDone})>(
        selector: (_, c) => (
          themeId: c.projectSettings.themeId,
          themeMode: c.appSettings.themeMode,
          onboardingDone: c.appSettings.hasCompletedOnboarding,
        ),
        builder: (context, selected, _) {
          final boardController = context.read<BoardController>();
          final preset = projectThemeForId(selected.themeId);
          return MaterialApp(
            title: '看板',
            debugShowCheckedModeBanner: false,
            navigatorKey: _navigatorKey,
            builder: (context, child) => CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape):
                    _dismissWithEscape,
              },
              child: AgentDispatchWindowHost(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            theme: buildKanbanTheme(preset, Brightness.light),
            darkTheme: buildKanbanTheme(preset, Brightness.dark),
            themeMode: selected.themeMode,
            locale: const Locale('zh', 'CN'),
            home: selected.onboardingDone
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
  DateTime? lastSyncedAt, {
  SyncProgress? progress,
  int pendingUploadCount = 0,
}) {
  if (status == SyncStatus.syncing) {
    return progress?.shortLabel ?? syncStatusLabel(status);
  }
  if (lastSyncedAt == null) {
    return syncStatusLabel(status);
  }
  if (status == SyncStatus.error) {
    return syncStatusLabel(status);
  }
  final base = '已同步 ${formatSyncTime(lastSyncedAt)}';
  if (pendingUploadCount <= 0) return base;
  return '$base · 待同步 $pendingUploadCount';
}

/// 窄屏顶栏使用的同步摘要，保留状态与最近成功同步日期。
String compactSyncStatusLabel(
  SyncStatus status,
  DateTime? lastSyncedAt, {
  SyncProgress? progress,
  int pendingUploadCount = 0,
}) {
  if (status == SyncStatus.syncing) {
    return progress?.shortLabel ?? syncStatusLabel(status);
  }
  final date = lastSyncedAt == null
      ? null
      : formatSyncTime(lastSyncedAt).split(' ').first;
  if (status == SyncStatus.error) {
    return date == null ? '同步失败' : '同步失败 · $date';
  }
  if (date == null) return syncStatusLabel(status);
  final base = '已同步 $date';
  if (pendingUploadCount <= 0) return base;
  return '待同步 $pendingUploadCount · $date';
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
