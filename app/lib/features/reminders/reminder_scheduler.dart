import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../models/kanban_models.dart';

class ReminderScheduler {
  ReminderScheduler({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const androidChannelId = 'kanban_reminders';
  static const androidChannelName = '任务提醒';
  static const androidChannelDescription = '卡片截止日期与自定义提醒';
  static const _settingsChannel = MethodChannel(
    'com.mikeken.kanban/notifications',
  );
  static const _initializeTimeout = Duration(seconds: 8);

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _initializeAttempted = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> initialize() async {
    if (_initialized || _initializeAttempted) return;
    _initializeAttempted = true;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(
        appName: '看板',
        appUserModelId: 'com.mikeken.kanban',
        guid: 'e44f9286-a41f-4bbd-a987-a038f9ab63ca',
      ),
    );
    try {
      await _plugin.initialize(settings: settings).timeout(_initializeTimeout);
      await _ensureAndroidChannel();
      _initialized = true;
    } on TimeoutException {
      debugPrint(
          'Local notification initialization timed out; skipped without affecting startup');
    } catch (error) {
      debugPrint('Failed to initialize local notifications: $error');
    }
  }

  /// 提前创建渠道，让系统设置页能显示「任务提醒」分类。
  Future<void> _ensureAndroidChannel() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        androidChannelId,
        androidChannelName,
        description: androidChannelDescription,
        importance: Importance.high,
      ),
    );
  }

  Future<bool> areNotificationsEnabled() async {
    await initialize();
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return await _android?.areNotificationsEnabled() ?? true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  /// 打开系统应用通知设置页（永久拒绝后的兜底）。
  Future<bool> openSystemNotificationSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      await _settingsChannel.invokeMethod<void>('openNotificationSettings');
      return true;
    } on MissingPluginException {
      debugPrint(
          'Failed to open notification settings: platform channel is not registered');
      return false;
    } on PlatformException catch (error) {
      debugPrint('Failed to open notification settings: $error');
      return false;
    }
  }

  Future<void> rescheduleAll(Map<String, KanbanBoard> boards) async {
    await initialize();
    if (!_initialized) return;
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
    if (!_initialized) return;
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
          androidChannelId,
          androidChannelName,
          channelDescription: androidChannelDescription,
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
    if (!_initialized) return;
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
