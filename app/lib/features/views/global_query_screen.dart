import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../common/app_snack_bar.dart';
import 'card_query_service.dart';
import 'card_reference.dart';
import 'filter_sheet.dart';
import 'filter_spec.dart';
import 'saved_view.dart';
import 'saved_views_screen.dart';

typedef LoadCardReferences = Future<List<CardReference>> Function();
typedef HandleCardReference = Future<void> Function(CardReference reference);
typedef PersistSavedView = Future<void> Function(
  String? id,
  String name,
  FilterSpec filter,
);
typedef RemoveSavedView = Future<void> Function(SavedView view);

/// 跨项目搜索、筛选并复用保存视图的统一入口。
class GlobalQueryScreen extends StatefulWidget {
  const GlobalQueryScreen({
    super.key,
    required this.loadCards,
    required this.onOpen,
    required this.onToggleCompleted,
    required this.labels,
    required this.savedViews,
    required this.onSaveView,
    required this.onDeleteView,
    this.initialFilter = const FilterSpec(),
  });

  final LoadCardReferences loadCards;
  final HandleCardReference onOpen;
  final HandleCardReference onToggleCompleted;
  final Map<String, String> labels;
  final List<SavedView> Function() savedViews;
  final PersistSavedView onSaveView;
  final RemoveSavedView onDeleteView;
  final FilterSpec initialFilter;

  @override
  State<GlobalQueryScreen> createState() => _GlobalQueryScreenState();
}

class _GlobalQueryScreenState extends State<GlobalQueryScreen> {
  final _searchController = TextEditingController();
  List<CardReference> _cards = const [];
  FilterSpec _filter = const FilterSpec();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter.copyWith(keyword: '');
    _searchController.text = widget.initialFilter.keyword;
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cards = await widget.loadCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  FilterSpec get _effectiveFilter => _filter.copyWith(
        keyword: _searchController.text,
      );

  Map<String, String> get _projects {
    final projects = <String, String>{};
    for (final card in _cards) {
      projects.putIfAbsent(
        card.projectId,
        () => card.projectName.isEmpty ? '未命名项目' : card.projectName,
      );
    }
    return Map.fromEntries(
      projects.entries.toList()
        ..sort((left, right) => left.value.compareTo(right.value)),
    );
  }

  Future<void> _showFilters() async {
    final picked = await showCardFilterSheet(
      context: context,
      initial: _filter,
      labels: widget.labels,
      projects: _projects,
      showSort: true,
    );
    if (picked != null && mounted) {
      setState(() => _filter = picked.copyWith(keyword: ''));
    }
  }

  Future<void> _saveCurrentView() async {
    var draftName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存当前视图'),
        content: TextFormField(
          key: const ValueKey('global-view-name'),
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
    if (name == null || name.isEmpty || !mounted) return;
    await widget.onSaveView(null, name, _effectiveFilter);
    if (!mounted) return;
    showAppSnackBar(context, message: '已保存视图「$name」');
  }

  Future<void> _manageViews() async {
    final selected = await Navigator.of(context).push<SavedView>(
      MaterialPageRoute<SavedView>(
        builder: (_) => SavedViewsScreen(
          views: widget.savedViews(),
          onRename: (view, name) =>
              widget.onSaveView(view.id, name, view.filter),
          onDelete: widget.onDeleteView,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _searchController.text = selected.filter.keyword;
    setState(() => _filter = selected.filter.copyWith(keyword: ''));
    showAppSnackBar(
      context,
      message: selected.isShowAll ? '已显示全部卡片' : '已应用「${selected.name}」',
      clearExisting: true,
    );
  }

  Future<void> _open(CardReference reference) async {
    await widget.onOpen(reference);
    if (mounted) await _load();
  }

  Future<void> _toggle(CardReference reference) async {
    await widget.onToggleCompleted(reference);
    if (mounted) await _load();
  }

  void _clear() {
    _searchController.clear();
    setState(() => _filter = const FilterSpec());
  }

  @override
  Widget build(BuildContext context) {
    final spec = _effectiveFilter;
    final results = const CardQueryService().query(_cards, spec);
    return Scaffold(
      appBar: AppBar(
        title: const Text('全部卡片'),
        actions: [
          IconButton(
            tooltip: spec.hasFilters ? '筛选已启用' : '筛选与排序',
            onPressed: _showFilters,
            icon: Badge(
              isLabelVisible: spec.hasFilters,
              child: const Icon(Icons.tune),
            ),
          ),
          IconButton(
            tooltip: '保存当前视图',
            onPressed: _saveCurrentView,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          IconButton(
            tooltip: '管理保存视图',
            onPressed: _manageViews,
            icon: const Icon(Icons.bookmarks_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const ValueKey('global-query-search'),
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索全部项目中的卡片',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: _buildBody(results, spec)),
        ],
      ),
    );
  }

  Widget _buildBody(List<CardReference> results, FilterSpec spec) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        title: '加载全部卡片失败',
        detail: _error!,
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (results.isEmpty) {
      return _MessageState(
        icon: spec.hasFilters ? Icons.search_off : Icons.inbox_outlined,
        title: spec.hasFilters ? '没有符合条件的卡片' : '还没有卡片',
        detail: spec.hasFilters ? '可以调整关键词或筛选条件' : '先在任一项目中添加卡片',
        actionLabel: spec.hasFilters ? '清除搜索和筛选' : null,
        onAction: spec.hasFilters ? _clear : null,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
        itemCount: results.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final card = results[index];
          return _GlobalCardTile(
            card: card,
            onOpen: () => _open(card),
            onToggleCompleted: () => _toggle(card),
          );
        },
      ),
    );
  }
}

class _GlobalCardTile extends StatelessWidget {
  const _GlobalCardTile({
    required this.card,
    required this.onOpen,
    required this.onToggleCompleted,
  });

  final CardReference card;
  final VoidCallback onOpen;
  final VoidCallback onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    final due = card.dueDate == null
        ? null
        : DateFormat.MMMd('zh_CN').format(
            DateTime.fromMillisecondsSinceEpoch(card.dueDate!),
          );
    final location = '${card.projectName} · ${card.columnName}';
    final semantics = [
      card.title,
      location,
      if (due != null) '$due到期',
      if (card.completed) '已完成',
    ].join('，');

    return Semantics(
      button: true,
      label: semantics,
      child: ListTile(
        leading: Checkbox(
          value: card.completed,
          onChanged: (_) => onToggleCompleted(),
        ),
        title: Text(
          card.title,
          style: card.completed
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(location),
        trailing: due == null ? null : Text(due),
        onTap: onOpen,
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: '$title，$detail',
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 56,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
