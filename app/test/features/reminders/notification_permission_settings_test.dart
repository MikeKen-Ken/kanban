import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kanban/features/project/project_list_preferences.dart';
import 'package:kanban/features/reminders/reminder_scheduler.dart';
import 'package:kanban/settings/app_settings.dart';

void main() {
  group('AppSettings 通知权限标记', () {
    test('默认未请求过通知权限', () {
      expect(
        AppSettings.platformDefault().hasRequestedNotificationPermission,
        isFalse,
      );
    });

    test('序列化往返保留 hasRequestedNotificationPermission', () {
      final settings = AppSettings(
        dragLongPressMs: 500,
        hasRequestedNotificationPermission: true,
        themeMode: ThemeMode.dark,
        projectSortMode: ProjectSortMode.defaultOrder,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.hasRequestedNotificationPermission, isTrue);
      expect(restored.themeMode, ThemeMode.dark);
    });

    test('旧 JSON 缺字段时默认为 false', () {
      final restored = AppSettings.fromJson({
        'dragLongPressMs': 0,
        'themeMode': 'system',
      });
      expect(restored.hasRequestedNotificationPermission, isFalse);
    });
  });

  group('ReminderScheduler.notificationIdFor', () {
    test('同一卡片 id 生成稳定通知 id', () {
      expect(
        ReminderScheduler.notificationIdFor('card-a'),
        ReminderScheduler.notificationIdFor('card-a'),
      );
    });

    test('不同卡片 id 通常生成不同通知 id', () {
      expect(
        ReminderScheduler.notificationIdFor('card-a'),
        isNot(ReminderScheduler.notificationIdFor('card-b')),
      );
    });
  });
}
