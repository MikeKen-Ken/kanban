import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../common/date_utils.dart';
import 'card_reference.dart';

class TodayViewScreen extends StatelessWidget {
  const TodayViewScreen({
    super.key,
    required this.cards,
    required this.onOpen,
    required this.onToggleCompleted,
  });

  final List<CardReference> cards;
  final ValueChanged<CardReference> onOpen;
  final ValueChanged<CardReference> onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final incomplete = cards
        .where((card) => !card.completed && card.dueDate != null)
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    final overdue =
        incomplete.where((card) => isOverdue(card.dueDate!, now)).toList();
    final today =
        incomplete.where((card) => isDueToday(card.dueDate!, now)).toList();
    final thisWeek = incomplete
        .where(
          (card) =>
              !isOverdue(card.dueDate!, now) &&
              !isDueToday(card.dueDate!, now) &&
              isDueThisWeek(card.dueDate!, now),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('今日')),
      body: overdue.isEmpty && today.isEmpty && thisWeek.isEmpty
          ? const _TodayEmptyState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (overdue.isNotEmpty)
                  _Section(
                    title: '已逾期',
                    cards: overdue,
                    color: Theme.of(context).colorScheme.error,
                    onOpen: onOpen,
                    onToggleCompleted: onToggleCompleted,
                  ),
                if (today.isNotEmpty)
                  _Section(
                    title: '今天',
                    cards: today,
                    onOpen: onOpen,
                    onToggleCompleted: onToggleCompleted,
                  ),
                if (thisWeek.isNotEmpty)
                  _Section(
                    title: '本周稍后',
                    cards: thisWeek,
                    onOpen: onOpen,
                    onToggleCompleted: onToggleCompleted,
                  ),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.cards,
    required this.onOpen,
    required this.onToggleCompleted,
    this.color,
  });

  final String title;
  final List<CardReference> cards;
  final ValueChanged<CardReference> onOpen;
  final ValueChanged<CardReference> onToggleCompleted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title，共 ${cards.length} 项',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              '$title · ${cards.length}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  _TodayCardTile(
                    card: cards[i],
                    onOpen: onOpen,
                    onToggleCompleted: onToggleCompleted,
                  ),
                  if (i < cards.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCardTile extends StatelessWidget {
  const _TodayCardTile({
    required this.card,
    required this.onOpen,
    required this.onToggleCompleted,
  });

  final CardReference card;
  final ValueChanged<CardReference> onOpen;
  final ValueChanged<CardReference> onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    final due = DateTime.fromMillisecondsSinceEpoch(card.dueDate!);
    return Semantics(
      button: true,
      label: '${card.title}，${card.projectName}，'
          '${DateFormat.MMMd('zh_CN').format(due)}到期',
      child: ListTile(
        leading: Checkbox(
          value: card.completed,
          onChanged: (_) => onToggleCompleted(card),
        ),
        title: Text(card.title),
        subtitle: Text('${card.projectName} · ${card.columnName}'),
        trailing: Text(DateFormat.MMMd('zh_CN').format(due)),
        onTap: () => onOpen(card),
      ),
    );
  }
}

class _TodayEmptyState extends StatelessWidget {
  const _TodayEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('今天没有待处理的到期任务',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '已逾期、今天到期和本周任务会集中显示在这里',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
