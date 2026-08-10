import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'due_date_shortcuts.dart';
import 'reminder_shortcuts.dart';

/// 截止日期与提醒区块（含快捷芯片与日期/时间选择）。
class CardDetailDueReminderSection extends StatelessWidget {
  const CardDetailDueReminderSection({
    super.key,
    required this.dueDate,
    required this.reminderAt,
    required this.onDueDateChanged,
    required this.onReminderChanged,
  });

  final DateTime? dueDate;
  final DateTime? reminderAt;
  final ValueChanged<DateTime?> onDueDateChanged;
  final ValueChanged<DateTime?> onReminderChanged;

  Future<void> _pickDueDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: '选择截止日期',
    );
    if (picked != null && context.mounted) {
      onDueDateChanged(picked);
    }
  }

  Future<void> _pickReminder(BuildContext context) async {
    final now = DateTime.now();
    final initial = reminderAt ?? dueDate ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 5),
      helpText: '选择提醒日期',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: '选择提醒时间',
    );
    if (time == null || !context.mounted) return;
    onReminderChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  /// 截止日期快捷预设与「设置日期」同一行；小屏可横向滚动。
  Widget _buildDueDateRow(BuildContext context) {
    final now = DateTime.now();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final shortcut in DueDateShortcut.values) ...[
            FilterChip(
              label: Text(shortcut.label),
              selected: isSameLocalDay(dueDate, shortcut.resolve(now)),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onSelected: (_) => onDueDateChanged(shortcut.resolve(now)),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.tonalIcon(
            onPressed: () => _pickDueDate(context),
            icon: const Icon(Icons.event, size: 18),
            label: Text(
              dueDate == null
                  ? '设置日期'
                  : DateFormat.yMMMd('zh_CN').format(dueDate!),
            ),
          ),
          if (dueDate != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => onDueDateChanged(null),
              child: const Text('清除'),
            ),
          ],
        ],
      ),
    );
  }

  /// 提醒快捷预设自动换行；「设置提醒 / 清除」始终留在布局流中，避免被横向滚动藏住。
  Widget _buildReminderRow(BuildContext context) {
    final now = DateTime.now();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final shortcut in ReminderShortcut.values)
          FilterChip(
            label: Text(shortcut.label),
            selected: isSameLocalMinute(reminderAt, shortcut.resolve(now)),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            // 再次点击已选中芯片则取消选择（清除提醒）。
            onSelected: (selected) {
              if (selected) {
                onReminderChanged(shortcut.resolve(now));
              } else {
                onReminderChanged(null);
              }
            },
          ),
        FilledButton.tonalIcon(
          onPressed: () => _pickReminder(context),
          icon: const Icon(Icons.notifications_outlined, size: 18),
          label: Text(
            reminderAt == null
                ? '设置提醒'
                : DateFormat('MMMd HH:mm', 'zh_CN').format(reminderAt!),
          ),
        ),
        if (reminderAt != null)
          TextButton(
            onPressed: () => onReminderChanged(null),
            child: const Text('清除'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('截止日期', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _buildDueDateRow(context),
        const SizedBox(height: 20),
        Text('提醒', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _buildReminderRow(context),
      ],
    );
  }
}
