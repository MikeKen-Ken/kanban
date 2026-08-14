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
        width: 560,
        height: 520,
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

class _TokenStatsBodyState extends State<_TokenStatsBody> {
  AgentDispatchTokenStats? _stats;

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

    final today = stats.today;
    final last7 = stats.lastDays(7);
    final last30 = stats.lastDays(30);
    final daily = stats.daily(7);
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(label: '会话数', value: '${stats.sessionCount}'),
            _MetricCard(
              label: '累计 Token',
              value: _formatCount(stats.totalTokens),
            ),
            _MetricCard(
              label: '平均每次',
              value: _formatCount(stats.averageTotal?.round() ?? 0),
            ),
            _MetricCard(
              label: '今日',
              value: _formatCount(today.totalTokens),
              subtitle: '${today.sessionCount} 次',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('输入 / 缓存 / 输出', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '输入 ${_formatCount(stats.totalInput)}'
          '（均 ${_formatCount(stats.averageInput?.round() ?? 0)}） · '
          '缓存读 ${_formatCount(stats.totalCacheRead)} · '
          '缓存写 ${_formatCount(stats.totalCacheWrite)} · '
          '输出 ${_formatCount(stats.totalOutput)}'
          '（均 ${_formatCount(stats.averageOutput?.round() ?? 0)}）',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _SplitBar(
          input: stats.totalInput,
          cache: stats.totalCacheRead + stats.totalCacheWrite,
          output: stats.totalOutput,
        ),
        const SizedBox(height: 20),
        Text('最近 7 天', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '共 ${_formatCount(last7.totalTokens)} token · '
          '${last7.sessionCount} 次 · '
          '日均 ${_formatCount(last7.sessionCount == 0 ? 0 : (last7.totalTokens / 7).round())}',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        _DailyBars(values: daily),
        const SizedBox(height: 20),
        Text('最近 30 天', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '共 ${_formatCount(last30.totalTokens)} token · ${last30.sessionCount} 次',
          style: textTheme.bodySmall,
        ),
        if (stats.peakSession != null) ...[
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.trending_up_outlined),
            title: const Text('单次峰值'),
            subtitle: Text(
              '${_formatCount(stats.peakSession!.totalTokens)} '
              '(入 ${_formatCount(stats.peakSession!.inputTokens)} / '
              '缓存 ${_formatCount(stats.peakSession!.cacheReadTokens + stats.peakSession!.cacheWriteTokens)} / '
              '出 ${_formatCount(stats.peakSession!.outputTokens)})',
            ),
          ),
        ],
        if (stats.lastSession != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('最近一次'),
            subtitle: Text(
              '${_formatCount(stats.lastSession!.totalTokens)} token · '
              '${_formatStamp(stats.lastSession!.at)}',
            ),
          ),
      ],
    );
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
