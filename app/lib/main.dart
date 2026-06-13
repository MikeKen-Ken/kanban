import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/board_controller.dart';
import 'features/project/project_theme.dart';
import 'screens/home_screen.dart';
import 'webdav_sync/webdav_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await BoardController.create();
  runApp(KanbanApp(controller: controller));
}

class KanbanApp extends StatelessWidget {
  const KanbanApp({super.key, required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: controller,
      child: Consumer<BoardController>(
        builder: (context, boardController, _) {
          final preset = projectThemeForId(boardController.projectSettings.themeId);
          return MaterialApp(
            title: '看板',
            debugShowCheckedModeBanner: false,
            theme: buildKanbanTheme(preset, Brightness.light),
            darkTheme: buildKanbanTheme(preset, Brightness.dark),
            locale: const Locale('zh', 'CN'),
            home: const HomeScreen(),
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
