import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/import_export/backup_retention.dart';
import 'package:kanban/settings/app_settings.dart';

void main() {
  group('autoBackupRetentionDaysLabel', () {
    test('0 means never', () {
      expect(autoBackupRetentionDaysLabel(0), '从不');
    });

    test('positive days', () {
      expect(autoBackupRetentionDaysLabel(14), '14 天');
    });
  });

  group('AppSettings autoBackupRetentionDays', () {
    test('default is 14', () {
      expect(AppSettings.platformDefault().autoBackupRetentionDays, 14);
    });

    test('round-trips through json', () {
      final settings = AppSettings(
        dragLongPressMs: 200,
        autoBackupRetentionDays: 30,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.autoBackupRetentionDays, 30);
    });

    test('missing json field defaults to 14', () {
      final restored = AppSettings.fromJson({'dragLongPressMs': 200});
      expect(restored.autoBackupRetentionDays, 14);
    });
  });
}
