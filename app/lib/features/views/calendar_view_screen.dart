import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../common/date_utils.dart';
import 'card_reference.dart';

/// 跨项目按到期日查看与调整卡片的日历视图。
class CalendarViewScreen extends StatefulWidget {
  const CalendarViewScreen({
    super.key,
    required this.loadCards,
    required this.onOpen,
    required this.onToggleCompleted,
    required this.onChangeDueDate,
    required this.onCreateForDay,
  });

  final Future<List<CardReference>> Function() loadCards;
  final Future<void> Function(CardReference reference) onOpen;
  final Future<void> Function(CardReference reference) onToggleCompleted;
  final Future<void> Function(CardReference card, DateTime day) onChangeDueDate;
  final Future<void> Function(DateTime day) onCreateForDay;

  @override
  State<CalendarViewScreen> createState() => _CalendarViewScreenState();
}

class _CalendarViewScreenState extends State<CalendarViewScreen> {
  late DateTime _month;
  DateTime? _selectedDay;
  List<CardReference> _cards = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selectedDay = startOfLocalDay(now);
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final cards = await widget.loadCards();
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _loading = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  Map<DateTime, List<CardReference>> _cardsByDay() {
    final map = <DateTime, List<CardReference>>{};
    for (final card in _cards) {
      final due = card.dueDate;
      if (due == null || card.completed) continue;
      final day = startOfLocalDay(DateTime.fromMillisecondsSinceEpoch(due));
      map.putIfAbsent(day, () => []).add(card);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    }
    return map;
  }

  List<DateTime> _daysInGrid() {
    final first = DateTime(_month.year, _month.month, 1);
    final start =
        first.subtract(Duration(days: first.weekday - DateTime.monday));
    return [for (var i = 0; i < 42; i++) start.add(Duration(days: i))];
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _cardsByDay();
    final selected = _selectedDay;
    final selectedCards =
        selected == null ? const <CardReference>[] : (byDay[selected] ?? const []);
    final theme = Theme.of(context);
    final today = startOfLocalDay(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('日历'),
        actions: [
          IconButton(
            tooltip: '上个月',
            onPressed: () => _shiftMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Center(
            child: Text(
              DateFormat.yMMMM('zh_CN').format(_month),
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: '下个月',
            onPressed: () => _shiftMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: '回到今天',
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                _month = DateTime(now.year, now.month);
                _selectedDay = startOfLocalDay(now);
              });
            },
            icon: const Icon(Icons.today_outlined),
          ),
        ],
      ),
      floatingActionButton: selected == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await widget.onCreateForDay(selected);
                await _reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('当天新建'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                        Expanded(
                          child: Center(
                            child: Text(
                              label,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: 42,
                    itemBuilder: (context, index) {
                      final day = _daysInGrid()[index];
                      final inMonth = day.month == _month.month;
                      final count = byDay[day]?.length ?? 0;
                      final isSelected = selected != null &&
                          day.year == selected.year &&
                          day.month == selected.month &&
                          day.day == selected.day;
                      final isToday = day == today;
                      return DragTarget<CardReference>(
                        onWillAcceptWithDetails: (_) => true,
                        onAcceptWithDetails: (details) async {
                          await widget.onChangeDueDate(details.data, day);
                          await _reload();
                          if (mounted) setState(() => _selectedDay = day);
                        },
                        builder: (context, candidate, rejected) {
                          final hovering = candidate.isNotEmpty;
                          return Material(
                            color: hovering
                                ? theme.colorScheme.primaryContainer
                                : isSelected
                                    ? theme.colorScheme.secondaryContainer
                                    : theme.colorScheme.surfaceContainerHighest
                                        .withValues(
                                        alpha: inMonth ? 1 : 0.45,
                                      ),
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() => _selectedDay = day),
                              onLongPress: () async {
                                await widget.onCreateForDay(day);
                                await _reload();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${day.day}',
                                      style:
                                          theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: isToday
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                        color: isToday
                                            ? theme.colorScheme.primary
                                            : inMonth
                                                ? null
                                                : theme.colorScheme
                                                    .onSurfaceVariant,
                                      ),
                                    ),
                                    if (count > 0) ...[
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '$count',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: theme.colorScheme.onPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  flex: 4,
                  child: selected == null
                      ? const Center(child: Text('选择一天查看任务'))
                      : selectedCards.isEmpty
                          ? Center(
                              child: Text(
                                '${DateFormat.MMMd('zh_CN').format(selected)} 暂无到期任务',
                              ),
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 8, 12, 96),
                              itemCount: selectedCards.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final card = selectedCards[index];
                                return LongPressDraggable<CardReference>(
                                  data: card,
                                  feedback: Material(
                                    elevation: 6,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(card.title),
                                    ),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.35,
                                    child: _CalendarCardTile(
                                      card: card,
                                      onOpen: () async {
                                        await widget.onOpen(card);
                                        await _reload();
                                      },
                                      onToggleCompleted: () async {
                                        await widget.onToggleCompleted(card);
                                        await _reload();
                                      },
                                    ),
                                  ),
                                  child: _CalendarCardTile(
                                    card: card,
                                    onOpen: () async {
                                      await widget.onOpen(card);
                                      await _reload();
                                    },
                                    onToggleCompleted: () async {
                                      await widget.onToggleCompleted(card);
                                      await _reload();
                                    },
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }
}

class _CalendarCardTile extends StatelessWidget {
  const _CalendarCardTile({
    required this.card,
    required this.onOpen,
    required this.onToggleCompleted,
  });

  final CardReference card;
  final VoidCallback onOpen;
  final VoidCallback onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: card.completed,
        onChanged: (_) => onToggleCompleted(),
      ),
      title: Text(card.title),
      subtitle: Text(card.projectName),
      onTap: onOpen,
    );
  }
}
