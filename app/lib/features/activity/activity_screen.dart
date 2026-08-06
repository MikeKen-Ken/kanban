import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import 'activity_models.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final events = context.watch<BoardController>().activeProjectActivity;
    return Scaffold(
      appBar: AppBar(title: const Text('活动历史')),
      body: events.isEmpty
          ? const Center(child: Text('还没有活动记录'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: events.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final event = events[index];
                final time =
                    DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
                final source = event.source;
                final subtitle = StringBuffer(
                  DateFormat('yyyy-MM-dd HH:mm').format(time),
                );
                if (source != ActivitySource.user) {
                  subtitle.write(' · ${source.label}');
                  final hint = source.recoveryHint;
                  if (hint.isNotEmpty) {
                    subtitle.write('\n$hint');
                  }
                }
                return ListTile(
                  leading: Icon(_iconFor(source)),
                  title: Text('${event.action.label}「${event.entityTitle}」'),
                  subtitle: Text(subtitle.toString()),
                  isThreeLine: source != ActivitySource.user,
                );
              },
            ),
    );
  }

  static IconData _iconFor(ActivitySource source) => switch (source) {
        ActivitySource.user => Icons.history,
        ActivitySource.mcp => Icons.smart_toy_outlined,
        ActivitySource.automation => Icons.auto_fix_high_outlined,
      };
}
