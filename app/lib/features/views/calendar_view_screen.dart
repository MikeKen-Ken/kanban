import 'dart:math' as math;

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

  /// 宽屏限制格子高度，避免桌面端出现夸张大方格。
  double _cellMaxHeight(double maxWidth) {
    if (maxWidth >= 1100) return 48;
    if (maxWidth >= 800) return 56;
    if (maxWidth >= 600) return 64;
    return 80;
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
          : LayoutBuilder(
              builder: (context, constraints) {
                const gridPadding = 8.0;
                const spacing = 4.0;
                final gridWidth = constraints.maxWidth - gridPadding * 2;
                final cellWidth = (gridWidth - spacing * 6) / 7;
                final cellHeight =
                    math.min(cellWidth, _cellMaxHeight(constraints.maxWidth));
                final aspectRatio =
                    cellWidth <= 0 ? 1.0 : cellWidth / cellHeight;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        children: [
                          for (final label in [
                            '一',
                            '二',
                            '三',
                            '四',
                            '五',
                            '六',
                            '日',
                          ])
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
                    Padding(
                      padding: const EdgeInsets.all(gridPadding),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: aspectRatio,
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
                              if (mounted) {
                                setState(() => _selectedDay = day);
                              }
                            },
                            builder: (context, candidate, rejected) {
                              final hovering = candidate.isNotEmpty;
                              final backgroundColor = hovering
                                  ? theme.colorScheme.primaryContainer
                                  : isSelected
                                      ? theme.colorScheme.secondaryContainer
                                      : inMonth
                                          ? theme.colorScheme
                                              .surfaceContainerHighest
                                          : theme.colorScheme.surfaceContainerLow;
                              final dateColor = isToday
                                  ? theme.colorScheme.primary
                                  : inMonth
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.62);
                              final semanticsLabel = '${day.month}月${day.day}日'
                                  '${isToday ? '，今天' : ''}'
                                  '${inMonth ? '' : '，非本月'}'
                                  '${count > 0 ? '，$count 项到期任务' : '，无到期任务'}';

                              return Semantics(
                                button: true,
                                selected: isSelected,
                                label: semanticsLabel,
                                child: Material(
                                  color: backgroundColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: isToday
                                          ? theme.colorScheme.primary
                                          : isSelected
                                              ? theme.colorScheme.secondary
                                              : Colors.transparent,
                                      width: isToday ? 2 : 1,
                                    ),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () =>
                                        setState(() => _selectedDay = day),
                                    onLongPress: () async {
                                      await widget.onCreateForDay(day);
                                      await _reload();
                                    },
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Align(
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${day.day}',
                                            style: theme.textTheme.labelLarge
                                                ?.copyWith(
                                              fontWeight: isToday
                                                  ? FontWeight.w800
                                                  : FontWeight.w500,
                                              color: dateColor,
                                            ),
                                          ),
                                        ),
                                        if (isToday)
                                          Positioned(
                                            top: 3,
                                            left: 3,
                                            child: Container(
                                              key: const ValueKey(
                                                'calendar-today-marker',
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.primary,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '今',
                                                style: theme.textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: theme.colorScheme
                                                      .onPrimary,
                                                  fontSize: 10,
                                                  height: 1.1,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (count > 0)
                                          Positioned(
                                            right: 3,
                                            bottom: 3,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 1,
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
                                                  color: theme
                                                      .colorScheme.onPrimary,
                                                  fontSize: 10,
                                                  height: 1.1,
                                                ),
                                              ),
                                            ),
                                          ),
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Text(
                        selected == null
                            ? '选择一天查看任务'
                            : '${DateFormat.yMMMd('zh_CN').format(selected)}'
                                ' · ${selectedCards.length} 项',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: selected == null
                          ? const SizedBox.shrink()
                          : selectedCards.isEmpty
                              ? Align(
                                  alignment: Alignment.topLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      4,
                                      16,
                                      8,
                                    ),
                                    child: Text(
                                      '这一天暂无到期任务',
                                      key: const ValueKey(
                                        'calendar-day-empty',
                                      ),
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    4,
                                    12,
                                    96,
                                  ),
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
                                            await widget
                                                .onToggleCompleted(card);
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
                );
              },
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
