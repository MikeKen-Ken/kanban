import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/trash/trash_auto_clear.dart';
import 'package:kanban/features/trash/trash_models.dart';
import 'package:kanban/settings/app_settings.dart';

void main() {
  group('selectExpiredTrashItems', () {
    final now = DateTime(2026, 8, 14, 12);

    TrashItem item({required int deletedAt}) => TrashItem(
          id: 'id-$deletedAt',
          type: TrashItemType.card,
          deletedAt: deletedAt,
          displayName: 'test',
          payload: const {},
        );

    test('retainDays <= 0 returns empty', () {
      expect(
        selectExpiredTrashItems(
          items: [item(deletedAt: 0)],
          retainDays: 0,
          now: now,
        ),
        isEmpty,
      );
    });

    test('returns items older than retainDays', () {
      final cutoff = now.subtract(const Duration(days: 7));
      final expired = cutoff.subtract(const Duration(hours: 1));
      final fresh = cutoff.add(const Duration(hours: 1));

      final result = selectExpiredTrashItems(
        items: [
          item(deletedAt: expired.millisecondsSinceEpoch),
          item(deletedAt: fresh.millisecondsSinceEpoch),
        ],
        retainDays: 7,
        now: now,
      );

      expect(result, hasLength(1));
      expect(result.first.deletedAt, expired.millisecondsSinceEpoch);
    });
  });

  group('trashRetentionDaysLabel', () {
    test('0 means never', () {
      expect(trashRetentionDaysLabel(0), '从不');
    });

    test('positive days', () {
      expect(trashRetentionDaysLabel(30), '30 天');
    });
  });

  group('AppSettings trashRetentionDays', () {
    test('default is 0', () {
      expect(AppSettings.platformDefault().trashRetentionDays, 0);
    });

    test('round-trips through json', () {
      final settings = AppSettings(
        dragLongPressMs: 200,
        trashRetentionDays: 30,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.trashRetentionDays, 30);
    });

    test('missing json field defaults to 0', () {
      final restored = AppSettings.fromJson({'dragLongPressMs': 200});
      expect(restored.trashRetentionDays, 0);
    });
  });
}
