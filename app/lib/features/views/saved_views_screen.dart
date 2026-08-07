import 'package:flutter/material.dart';

import 'saved_view.dart';
import '../../common/app_snack_bar.dart';

typedef RenameSavedView = Future<void> Function(SavedView view, String name);
typedef DeleteSavedView = Future<void> Function(SavedView view);

/// 管理保存视图，并在用户应用某个视图时将其返回给调用方。
class SavedViewsScreen extends StatefulWidget {
  const SavedViewsScreen({
    super.key,
    required this.views,
    required this.onRename,
    required this.onDelete,
  });

  final List<SavedView> views;
  final RenameSavedView onRename;
  final DeleteSavedView onDelete;

  @override
  State<SavedViewsScreen> createState() => _SavedViewsScreenState();
}

class _SavedViewsScreenState extends State<SavedViewsScreen> {
  late List<SavedView> _views;

  @override
  void initState() {
    super.initState();
    _views = _sorted(widget.views);
  }

  List<SavedView> _sorted(Iterable<SavedView> views) {
    return [...views]..sort((left, right) {
        final byName = left.name.toLowerCase().compareTo(
              right.name.toLowerCase(),
            );
        return byName != 0 ? byName : left.id.compareTo(right.id);
      });
  }

  Future<void> _rename(SavedView view) async {
    var draftName = view.name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名保存视图'),
        content: TextFormField(
          key: const ValueKey('saved-view-name'),
          initialValue: view.name,
          autofocus: true,
          decoration: const InputDecoration(labelText: '视图名称'),
          onChanged: (value) => draftName = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draftName.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == view.name || !mounted) return;

    await widget.onRename(view, name);
    if (!mounted) return;
    setState(() {
      _views = _sorted([
        for (final item in _views)
          if (item.id == view.id)
            SavedView(
              id: item.id,
              name: name,
              filter: item.filter,
              createdAt: item.createdAt,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            )
          else
            item,
      ]);
    });
    showAppSnackBar(context, message: '已重命名为「$name」');
  }

  Future<void> _delete(SavedView view) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除保存视图'),
        content: Text('确定删除「${view.name}」吗？卡片不会受到影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await widget.onDelete(view);
    if (!mounted) return;
    setState(() => _views.removeWhere((item) => item.id == view.id));
    showAppSnackBar(context, message: '已删除「${view.name}」');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('保存视图')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: 1 + (_views.isEmpty ? 1 : _views.length),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == 0) {
            return ListTile(
              key: const ValueKey('saved-view-show-all'),
              leading: const Icon(Icons.filter_alt_off_outlined),
              title: const Text('显示全部'),
              subtitle: const Text('清除搜索和筛选'),
              onTap: () => Navigator.pop(context, SavedView.showAll),
            );
          }
          if (_views.isEmpty) {
            return const _SavedViewsEmptyState();
          }
          final view = _views[index - 1];
          return ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: Text(view.name),
            subtitle: Text(_filterSummary(view)),
            onTap: () => Navigator.pop(context, view),
            trailing: PopupMenuButton<String>(
              tooltip: '管理「${view.name}」',
              onSelected: (action) {
                if (action == 'rename') {
                  _rename(view);
                } else if (action == 'delete') {
                  _delete(view);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('重命名'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('删除'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _filterSummary(SavedView view) {
    final parts = <String>[];
    final filter = view.filter;
    if (filter.keyword.trim().isNotEmpty) parts.add('关键词：${filter.keyword}');
    if (filter.projectIds.isNotEmpty) {
      parts.add('${filter.projectIds.length} 个项目');
    }
    if (filter.labelIds.isNotEmpty) parts.add('${filter.labelIds.length} 个标签');
    if (filter.priorities.isNotEmpty) {
      parts.add('${filter.priorities.length} 个优先级');
    }
    if (filter.dueDate.name != 'any') parts.add('日期条件');
    if (filter.completion.name != 'any') parts.add('状态条件');
    return parts.isEmpty ? '显示全部卡片' : parts.join(' · ');
  }
}

class _SavedViewsEmptyState extends StatelessWidget {
  const _SavedViewsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bookmarks_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '还没有保存视图',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '在“全部卡片”中设置搜索和筛选后即可保存',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
