import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/confirm_delete_card.dart';
import 'package:kanban/settings/app_settings.dart';

void main() {
  group('AppSettings 删除前确认', () {
    test('默认关闭（不弹确认）', () {
      expect(AppSettings.platformDefault().confirmBeforeDeleteCard, isFalse);
    });

    test('序列化往返保留开关', () {
      final settings = AppSettings(
        dragLongPressMs: 200,
        confirmBeforeDeleteCard: true,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.confirmBeforeDeleteCard, isTrue);
    });

    test('旧 JSON 缺字段时默认为 false', () {
      final restored = AppSettings.fromJson({
        'dragLongPressMs': 0,
        'themeMode': 'system',
      });
      expect(restored.confirmBeforeDeleteCard, isFalse);
    });

    test('copyWith 可开启与关闭', () {
      final base = AppSettings.platformDefault();
      expect(base.copyWith(confirmBeforeDeleteCard: true).confirmBeforeDeleteCard,
          isTrue);
      expect(
        base
            .copyWith(confirmBeforeDeleteCard: true)
            .copyWith(confirmBeforeDeleteCard: false)
            .confirmBeforeDeleteCard,
        isFalse,
      );
    });
  });

  group('resolveCardDeleteConfirmation', () {
    test('偏好关闭时不调用 prompt，直接允许删除', () async {
      var promptCalls = 0;
      final ok = await resolveCardDeleteConfirmation(
        confirmBeforeDelete: false,
        prompt: () async {
          promptCalls++;
          return false;
        },
      );
      expect(ok, isTrue);
      expect(promptCalls, 0);
    });

    test('偏好开启且用户确认 → 允许删除', () async {
      final ok = await resolveCardDeleteConfirmation(
        confirmBeforeDelete: true,
        prompt: () async => true,
      );
      expect(ok, isTrue);
    });

    test('偏好开启且用户取消 → 不删除', () async {
      final ok = await resolveCardDeleteConfirmation(
        confirmBeforeDelete: true,
        prompt: () async => false,
      );
      expect(ok, isFalse);
    });

    test('偏好开启且对话框关闭（null）→ 不删除', () async {
      final ok = await resolveCardDeleteConfirmation(
        confirmBeforeDelete: true,
        prompt: () async => null,
      );
      expect(ok, isFalse);
    });
  });
}
