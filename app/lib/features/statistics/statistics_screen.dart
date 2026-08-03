import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import 'statistics_service.dart';

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: FutureBuilder<KanbanStatistics>(
        future: context.read<BoardController>().loadStatistics(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(label: '全部', value: data.total),
                  _MetricCard(label: '进行中', value: data.active),
                  _MetricCard(label: '已完成', value: data.completed),
                  _MetricCard(
                    label: '已逾期',
                    value: data.overdue,
                    isAlert: data.overdue > 0,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('最近 7 天完成量', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _CompletionBars(values: data.completedLast7Days),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timer_outlined),
                title: const Text('平均完成耗时'),
                subtitle: Text(
                  data.averageCompletionHours == null
                      ? '暂无足够数据'
                      : '${data.averageCompletionHours!.toStringAsFixed(1)} 小时',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.isAlert = false,
  });

  final String label;
  final int value;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    final color = isAlert
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Semantics(
      label: '$label $value',
      child: SizedBox(
        width: 140,
        child: Card(
          color: color,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                const SizedBox(height: 8),
                Text('$value',
                    style: Theme.of(context).textTheme.headlineMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletionBars extends StatelessWidget {
  const _CompletionBars({required this.values});

  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(
        1, (maximum, value) => value > maximum ? value : maximum);
    return SizedBox(
      height: 128,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Semantics(
                label: '${i + 1} 天前完成 ${values[i]} 项',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${values[i]}'),
                      const SizedBox(height: 4),
                      Container(
                        height: 12 + 80 * values[i] / maxValue,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
