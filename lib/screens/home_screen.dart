import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/board_controller.dart';
import '../features/project/project_switcher.dart';
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
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<BoardController>();
    controller.syncStatusStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            title: const ProjectSwitcher(),
            actions: [
              IconButton(
                tooltip: _showSearch ? '关闭搜索' : '搜索卡片',
                icon: Icon(
                  _showSearch ? Icons.search_off : Icons.search,
                ),
                onPressed: () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) {
                      _searchController.clear();
                      _searchQuery = '';
                    }
                  });
                },
              ),
              _SyncIndicator(
                status: controller.syncStatus,
                error: controller.syncError,
                onTap: () => controller.syncNow(),
              ),
              IconButton(
                tooltip: '设置',
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
            bottom: _showSearch
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(56),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SearchBar(
                        controller: _searchController,
                        hintText: '搜索标题、备注、标签、子任务…',
                        leading: const Icon(Icons.search, size: 20),
                        trailing: _searchQuery.isNotEmpty
                            ? [
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                ),
                              ]
                            : null,
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                  )
                : null,
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
                      return KanbanColumnWidget(
                        column: column,
                        searchQuery: _searchQuery,
                      );
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
