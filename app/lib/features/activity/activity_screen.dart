import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';

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
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text('${event.action.label}「${event.entityTitle}」'),
                  subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(time)),
                );
              },
            ),
    );
  }
}
