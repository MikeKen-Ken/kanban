import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/kanban_labels.dart';

void main() {
  group('预设标签（艾森豪威尔）', () {
    test('新预设为四象限 + 缺资源，含短名与完整说明', () {
      final presets = presetKanbanLabels();
      expect(presets.map((l) => l.key).toList(), [
        'important_urgent',
        'important_not_urgent',
        'urgent_not_important',
        'not_urgent_not_important',
        'need_resource',
      ]);
      expect(presets.map((l) => l.name).toList(), [
        '重急',
        '重缓',
        '轻急',
        '轻缓',
        '缺资源',
      ]);
      expect(
        presets
            .where((l) => l.key != 'need_resource')
            .map((l) => l.description)
            .toList(),
        ['重要且紧急', '重要不紧急', '紧急不重要', '不重要不紧急'],
      );
      expect(
        presets.singleWhere((l) => l.key == 'need_resource').description,
        isNull,
      );
    });

    test('选标签列表不含旧预置 key', () {
      final keys = allKanbanLabels(const []).map((l) => l.key).toSet();
      expect(keys.intersection(kLegacyPresetLabelKeys), isEmpty);
      expect(keys.containsAll(kPresetLabelKeys), isTrue);
    });

    test('编辑列表在已选旧 key 时追加该项', () {
      final editing = labelsForEditing(
        const [],
        selectedKeys: const ['work', 'important_urgent'],
      );
      expect(editing.map((l) => l.key), contains('work'));
      expect(editing.where((l) => l.key == 'work').single.name, '工作（旧）');
      // 新预置仍在，且不重复
      expect(
        editing.where((l) => l.key == 'important_urgent'),
        hasLength(1),
      );
    });
  });

  group('旧预置兼容', () {
    test('work/personal/urgent/idea 仍可解析为带（旧）的友好名', () {
      expect(findKanbanLabel('work')?.name, '工作（旧）');
      expect(findKanbanLabel('personal')?.name, '个人（旧）');
      expect(findKanbanLabel('urgent')?.name, '紧急（旧）');
      expect(findKanbanLabel('idea')?.name, '想法（旧）');
    });

    test('旧 key 不出现在 presetKanbanLabels', () {
      final keys = presetKanbanLabels().map((l) => l.key).toSet();
      for (final key in kLegacyPresetLabelKeys) {
        expect(keys.contains(key), isFalse);
      }
    });

    test('自定义标签优先于预置与旧预置', () {
      final custom = [
        KanbanLabel(
          key: 'work',
          name: '我的工作',
          color: const Color(0xFF112233),
        ),
      ];
      expect(findKanbanLabel('work', custom)?.name, '我的工作');
    });
  });
}
