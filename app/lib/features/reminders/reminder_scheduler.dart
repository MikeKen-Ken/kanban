import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../models/kanban_models.dart';

class ReminderScheduler {
  ReminderScheduler({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(
        appName: '看板',
        appUserModelId: 'com.mikeken.kanban',
        guid: 'e44f9286-a41f-4bbd-a987-a038f9ab63ca',
      ),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ??
        false;
  }

  Future<void> rescheduleAll(Map<String, KanbanBoard> boards) async {
    await initialize();
    await _plugin.cancelAll();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in boards.entries) {
      for (final column in entry.value.columns) {
        for (final card in column.cards) {
          final reminderAt = card.reminderAt;
          if (card.completed || reminderAt == null || reminderAt <= now) {
            continue;
          }
          await schedule(
            projectId: entry.key,
            columnId: column.id,
            card: card,
          );
        }
      }
    }
  }

  Future<void> schedule({
    required String projectId,
    required String columnId,
    required KanbanCard card,
  }) async {
    final reminderAt = card.reminderAt;
    if (reminderAt == null || card.completed) return;
    await initialize();
    final instant = DateTime.fromMillisecondsSinceEpoch(
      reminderAt,
      isUtc: true,
    );
    await _plugin.zonedSchedule(
      id: notificationIdFor(card.id),
      title: card.title,
      body: card.dueDate == null ? '任务提醒' : '任务即将到期',
      scheduledDate: tz.TZDateTime.from(instant, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'kanban_reminders',
          '任务提醒',
          channelDescription: '卡片截止日期与自定义提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        windows: WindowsNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: '$projectId|$columnId|${card.id}',
    );
  }

  Future<void> cancel(String cardId) async {
    await initialize();
    await _plugin.cancel(id: notificationIdFor(cardId));
  }

  @visibleForTesting
  static int notificationIdFor(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
