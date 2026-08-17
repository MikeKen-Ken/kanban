import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_dispatch_token.dart';
import 'agent_dispatch_token_store.dart';

/// 工作台内的 Token 统计二级窗口。
Future<void> showAgentDispatchTokenStatsDialog({
  required BuildContext context,
  required String projectId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Token 统计'),
      content: SizedBox(
        width: 640,
        height: 560,
        child: _TokenStatsBody(projectId: projectId),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class _TokenStatsBody extends StatefulWidget {
  const _TokenStatsBody({required this.projectId});

  final String projectId;

  @override
  State<_TokenStatsBody> createState() => _TokenStatsBodyState();
}

enum _TokenRange {
  lastHour,
  today,
  last3Days,
  last7Days,
  last30Days,
  all,
}

class _TokenStatsBodyState extends State<_TokenStatsBody> {
  AgentDispatchTokenStats? _stats;
  _TokenRange _range = _TokenRange.last7Days;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final records = prefs.loadAgentDispatchTokens(projectId: widget.projectId);
    if (!mounted) return;
    setState(() {
      _stats = AgentDispatchTokenStats(records: records, now: DateTime.now());
    });
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空 Token 统计？'),
        content: const Text('将删除本机当前项目的全部会话用量记录，且不会同步到其他设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clearAgentDispatchTokens(projectId: widget.projectId);
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    if (stats == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (stats.sessionCount == 0) {
      return const Center(
        child: Text('暂无会话用量。完成一次 Cursor 调度后会在此按日汇总。'),
      );
    }

    final selected = _selectedStats(stats);
    final dailyDays = _dailyDays;
    final daily = dailyDays == null ? const <AgentDispatchDailyToken>[] : stats.daily(dailyDays);
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('清空统计'),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in _TokenRange.values)
              ChoiceChip(
                label: Text(_rangeLabel(option)),
                selected: _range == option,
                onSelected: (_) => setState(() => _range = option),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(label: '会话数', value: '${selected.sessionCount}'),
            _MetricCard(
              label: '合计 Token',
              value: _formatCount(selected.totalTokens),
            ),
            _MetricCard(
              label: '平均每次',
              value: _formatCount(selected.averageTotal?.round() ?? 0),
            ),
            _MetricCard(
              label: '全部累计',
              value: _formatCount(stats.totalTokens),
              subtitle: '${stats.sessionCount} 次',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('输入 / 缓存 / 输出', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '口径与官网 Dashboard 一致：Total = Input + Cache Read + Cache Write + Output，'
          '不把缓存再计入 Input。',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          '输入 ${_formatCount(selected.totalInput)}'
          '（均 ${_formatCount(selected.averageInput?.round() ?? 0)}） · '
          '缓存读 ${_formatCount(selected.totalCacheRead)} · '
          '缓存写 ${_formatCount(selected.totalCacheWrite)} · '
          '输出 ${_formatCount(selected.totalOutput)}'
          '（均 ${_formatCount(selected.averageOutput?.round() ?? 0)}）',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _SplitBar(
          input: selected.totalInput,
          cache: selected.totalCacheRead + selected.totalCacheWrite,
          output: selected.totalOutput,
        ),
        if (daily.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('按日明细', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '共 ${_formatCount(selected.totalTokens)} token · '
            '${selected.sessionCount} 次'
            '${dailyDays == null ? '' : ' · 日均 ${_formatCount(selected.sessionCount == 0 ? 0 : (selected.totalTokens / dailyDays).round())}'}',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (daily.length <= 10) _DailyBars(values: daily),
          const SizedBox(height: 12),
          _DailyTable(values: daily),
        ],
        if (selected.peakSession != null) ...[
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.trending_up_outlined),
            title: const Text('单次峰值'),
            subtitle: Text(
              '${_formatCount(selected.peakSession!.totalTokens)} '
              '(入 ${_formatCount(selected.peakSession!.inputTokens)} / '
              '缓存 ${_formatCount(selected.peakSession!.cacheReadTokens + selected.peakSession!.cacheWriteTokens)} / '
              '出 ${_formatCount(selected.peakSession!.outputTokens)})',
            ),
          ),
        ],
        if (selected.lastSession != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('最近一次'),
            subtitle: Text(
              '${_formatCount(selected.lastSession!.totalTokens)} token · '
              '${_formatStamp(selected.lastSession!.at)}',
            ),
          ),
      ],
    );
  }

  AgentDispatchTokenStats _selectedStats(AgentDispatchTokenStats stats) {
    return switch (_range) {
      _TokenRange.lastHour => stats.lastHours(1),
      _TokenRange.today => stats.today,
      _TokenRange.last3Days => stats.lastDays(3),
      _TokenRange.last7Days => stats.lastDays(7),
      _TokenRange.last30Days => stats.lastDays(30),
      _TokenRange.all => stats,
    };
  }

  int? get _dailyDays {
    return switch (_range) {
      _TokenRange.lastHour => null,
      _TokenRange.today => 1,
      _TokenRange.last3Days => 3,
      _TokenRange.last7Days => 7,
      _TokenRange.last30Days => 30,
      _TokenRange.all => null,
    };
  }

  String _rangeLabel(_TokenRange range) {
    return switch (range) {
      _TokenRange.lastHour => '过去 1 小时',
      _TokenRange.today => '今天',
      _TokenRange.last3Days => '近 3 天',
      _TokenRange.last7Days => '近 7 天',
      _TokenRange.last30Days => '近 30 天',
      _TokenRange.all => '全部',
    };
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.subtitle,
  });

  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null)
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitBar extends StatelessWidget {
  const _SplitBar({
    required this.input,
    required this.cache,
    required this.output,
  });

  final int input;
  final int cache;
  final int output;

  @override
  Widget build(BuildContext context) {
    final total = input + cache + output;
    if (total <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            Expanded(
              flex: input.clamp(1, total),
              child: ColoredBox(color: scheme.primary),
            ),
            if (cache > 0)
              Expanded(
                flex: cache.clamp(1, total),
                child: ColoredBox(color: scheme.secondary),
              ),
            Expanded(
              flex: output.clamp(1, total),
              child: ColoredBox(color: scheme.tertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.values});

  final List<AgentDispatchDailyToken> values;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(
      1,
      (maximum, item) => item.totalTokens > maximum ? item.totalTokens : maximum,
    );
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _formatCount(day.totalTokens),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 12 + 80 * day.totalTokens / maxValue,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${day.day.month}/${day.day.day}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DailyTable extends StatelessWidget {
  const _DailyTable({required this.values});

  final List<AgentDispatchDailyToken> values;

  @override
  Widget build(BuildContext context) {
    final rows = values.reversed.where((day) => day.sessions > 0).toList();
    if (rows.isEmpty) {
      return Text('该范围内暂无会话。', style: Theme.of(context).textTheme.bodySmall);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 36,
        columns: const [
          DataColumn(label: Text('日期')),
          DataColumn(label: Text('次数'), numeric: true),
          DataColumn(label: Text('Input'), numeric: true),
          DataColumn(label: Text('Cache Read'), numeric: true),
          DataColumn(label: Text('Cache Write'), numeric: true),
          DataColumn(label: Text('Output'), numeric: true),
          DataColumn(label: Text('Total'), numeric: true),
        ],
        rows: [
          for (final day in rows)
            DataRow(
              cells: [
                DataCell(Text('${day.day.month}/${day.day.day}')),
                DataCell(Text('${day.sessions}')),
                DataCell(Text(_formatCount(day.inputTokens))),
                DataCell(Text(_formatCount(day.cacheReadTokens))),
                DataCell(Text(_formatCount(day.cacheWriteTokens))),
                DataCell(Text(_formatCount(day.outputTokens))),
                DataCell(Text(_formatCount(day.totalTokens))),
              ],
            ),
        ],
      ),
    );
  }
}

String _formatCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 10000) {
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
  return '$value';
}

String _formatStamp(DateTime at) {
  final local = at.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$mm-$dd $hh:$min';
}
