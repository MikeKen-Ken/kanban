import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/commit_list_draft.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  group('commitChecklistDraft', () {
    test('空白草稿忽略，返回原列表引用', () {
      final items = [
        ChecklistItem(id: 'a', text: '已有项'),
      ];
      expect(
        identical(
          commitChecklistDraft(
            items: items,
            draftText: '',
            newId: () => 'new',
          ),
          items,
        ),
        isTrue,
      );
      expect(
        identical(
          commitChecklistDraft(
            items: items,
            draftText: '  \n\t',
            newId: () => 'new',
          ),
          items,
        ),
        isTrue,
      );
    });

    test('非空草稿 trim 后追加为未完成项', () {
      final items = [
        ChecklistItem(id: 'a', text: '已有项', completed: true),
      ];
      final next = commitChecklistDraft(
        items: items,
        draftText: '  新草稿  ',
        newId: () => 'draft-id',
      );
      expect(next.length, 2);
      expect(next.first.id, 'a');
      expect(next.last.id, 'draft-id');
      expect(next.last.text, '新草稿');
      expect(next.last.completed, isFalse);
    });

    test('空列表也可追加草稿', () {
      final next = commitChecklistDraft(
        items: const [],
        draftText: '仅草稿',
        newId: () => 'only',
      );
      expect(next.single.id, 'only');
      expect(next.single.text, '仅草稿');
    });
  });
}
