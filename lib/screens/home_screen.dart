import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/board_controller.dart';
import '../main.dart';
import '../webdav_sync/webdav_sync_service.dart';
import 'settings_screen.dart';
import '../widgets/kanban_column_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    final controller = context.read<BoardController>();
    controller.syncStatusStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _addColumn(BuildContext context) async {
    final controller = context.read<BoardController>();
    final textController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建列'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '列名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) {
      await controller.addColumn(title);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BoardController>(
      builder: (context, controller, _) {
        if (controller.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final board = controller.board;
        if (board == null) {
          return Scaffold(
            body: Center(child: Text(controller.errorMessage ?? '加载失败')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(board.title),
            actions: [
              _SyncIndicator(
                status: controller.syncStatus,
                error: controller.syncError,
                onTap: () => controller.syncNow(),
              ),
              IconButton(
                tooltip: '同步设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addColumn(context),
            icon: const Icon(Icons.add),
            label: const Text('新建列'),
          ),
          body: board.columns.isEmpty
              ? const Center(child: Text('点击右下角添加第一列'))
              : Scrollbar(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(16),
                    itemCount: board.columns.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final column = board.columns[index];
                      return KanbanColumnWidget(column: column);
                    },
                  ),
                ),
        );
      },
    );
  }
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({
    required this.status,
    required this.onTap,
    this.error,
  });

  final SyncStatus status;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SyncStatus.error => Theme.of(context).colorScheme.error,
      SyncStatus.success => Colors.green,
      SyncStatus.syncing => Theme.of(context).colorScheme.primary,
      SyncStatus.idle => null,
    };

    return Tooltip(
      message: error ?? '点击立即同步',
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(syncStatusIcon(status), color: color, size: 20),
        label: Text(
          syncStatusLabel(status),
          style: TextStyle(color: color, fontSize: 13),
        ),
      ),
    );
  }
}
