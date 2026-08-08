import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/edit_checklist_item.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  group('resolveChecklistItemDialogResult', () {
    test('点击遮罩关闭且输入已清空时返回空字符串，以便删除该项', () {
      expect(
        resolveChecklistItemDialogResult(
          dialogResult: null,
          draftText: '   ',
        ),
        '',
      );
    });

    test('点击遮罩关闭但输入仍非空时保留取消语义', () {
      expect(
        resolveChecklistItemDialogResult(
          dialogResult: null,
          draftText: '尚未保存的修改',
        ),
        isNull,
      );
    });

    test('按钮返回值优先于输入框快照', () {
      expect(
        resolveChecklistItemDialogResult(
          dialogResult: '保存后的文本',
          draftText: '',
        ),
        '保存后的文本',
      );
    });
  });

  group('applyChecklistItemEdit', () {
    final items = [
      ChecklistItem(id: 'a', text: '子任务甲', completed: true),
      ChecklistItem(id: 'b', text: '子任务乙'),
    ];

    test('取消且文本非空（dialogResult 为 null）→ 保留原列表引用', () {
      expect(
        identical(
          applyChecklistItemEdit(
            items: items,
            id: 'a',
            dialogResult: null,
          ),
          items,
        ),
        isTrue,
      );
    });

    test('清空后保存（空字符串）→ 删除该项', () {
      final next = applyChecklistItemEdit(
        items: items,
        id: 'a',
        dialogResult: '',
      );
      expect(next.map((e) => e.id).toList(), ['b']);
      expect(next.single.text, '子任务乙');
    });

    test('清空后取消（空字符串）→ 同样删除该项', () {
      final next = applyChecklistItemEdit(
        items: items,
        id: 'b',
        dialogResult: '',
      );
      expect(next.map((e) => e.id).toList(), ['a']);
      expect(next.single.text, '子任务甲');
    });

    test('非空保存 → 更新该项文本，保留完成状态', () {
      final next = applyChecklistItemEdit(
        items: items,
        id: 'a',
        dialogResult: '改后的子任务',
      );
      expect(next.length, 2);
      expect(next.first.id, 'a');
      expect(next.first.text, '改后的子任务');
      expect(next.first.completed, isTrue);
      expect(next.last.id, 'b');
      expect(next.last.text, '子任务乙');
    });

    test('验证反馈列表：清空删除与非空更新行为一致', () {
      final feedback = [
        ChecklistItem(id: 'vf1', text: '缺少截图'),
        ChecklistItem(id: 'vf2', text: '文案错误', completed: true),
      ];

      final deleted = applyChecklistItemEdit(
        items: feedback,
        id: 'vf1',
        dialogResult: '',
      );
      expect(deleted.map((e) => e.id).toList(), ['vf2']);

      final updated = applyChecklistItemEdit(
        items: feedback,
        id: 'vf2',
        dialogResult: '已修正文案',
      );
      expect(updated.first.text, '缺少截图');
      expect(updated.last.text, '已修正文案');
      expect(updated.last.completed, isTrue);

      expect(
        identical(
          applyChecklistItemEdit(
            items: feedback,
            id: 'vf1',
            dialogResult: null,
          ),
          feedback,
        ),
        isTrue,
      );
    });

    test('目标 id 不存在时：空结果得到空过滤列表，非空结果原样拷贝', () {
      final deleted = applyChecklistItemEdit(
        items: items,
        id: 'missing',
        dialogResult: '',
      );
      expect(deleted.map((e) => e.id).toList(), ['a', 'b']);

      final updated = applyChecklistItemEdit(
        items: items,
        id: 'missing',
        dialogResult: '不会命中',
      );
      expect(updated.map((e) => e.id).toList(), ['a', 'b']);
      expect(updated.first.text, '子任务甲');
    });
  });
}
