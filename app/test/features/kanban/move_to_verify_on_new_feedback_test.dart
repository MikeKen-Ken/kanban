import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/move_to_verify_on_new_feedback.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  group('hasAddedVerificationFeedbackItems', () {
    test('新增 id 视为新增', () {
      expect(
        hasAddedVerificationFeedbackItems(
          original: [ChecklistItem(id: 'a', text: '旧')],
          next: [
            ChecklistItem(id: 'a', text: '旧'),
            ChecklistItem(id: 'b', text: '新'),
          ],
        ),
        isTrue,
      );
    });

    test('仅改文案或勾选不算新增', () {
      expect(
        hasAddedVerificationFeedbackItems(
          original: [ChecklistItem(id: 'a', text: '旧')],
          next: [ChecklistItem(id: 'a', text: '改过', completed: true)],
        ),
        isFalse,
      );
    });

    test('仅删除不算新增', () {
      expect(
        hasAddedVerificationFeedbackItems(
          original: [
            ChecklistItem(id: 'a', text: '一'),
            ChecklistItem(id: 'b', text: '二'),
          ],
          next: [ChecklistItem(id: 'a', text: '一')],
        ),
        isFalse,
      );
    });

    test('空到非空算新增', () {
      expect(
        hasAddedVerificationFeedbackItems(
          original: const [],
          next: [ChecklistItem(id: 'n', text: '草稿提交')],
        ),
        isTrue,
      );
    });
  });

  group('findVerifyColumn', () {
    test('按标题解析，列 id 可自定义', () {
      final col = KanbanColumn(
        id: 'col-xyz',
        title: '待验证',
        order: 0,
        cards: const [],
      );
      expect(findVerifyColumn([col])?.id, 'col-xyz');
    });

    test('标题不符时回退默认 id verify', () {
      final col = KanbanColumn(
        id: 'verify',
        title: '验收中',
        order: 0,
        cards: const [],
      );
      expect(findVerifyColumn([col])?.id, 'verify');
    });

    test('找不到返回 null', () {
      expect(
        findVerifyColumn([
          KanbanColumn(id: 'todo', title: '待办', order: 0, cards: const []),
        ]),
        isNull,
      );
    });
  });

  group('targetVerifyColumnIdIfNeeded', () {
    final columns = [
      KanbanColumn(id: 'doing', title: '进行中', order: 0, cards: const []),
      KanbanColumn(id: 'verify', title: '待验证', order: 1, cards: const []),
    ];

    test('新增 VF 且不在待验证 → 返回待验证列 id', () {
      expect(
        targetVerifyColumnIdIfNeeded(
          originalFeedback: const [],
          nextFeedback: [ChecklistItem(id: 'vf1', text: '请验')],
          currentColumnId: 'doing',
          columns: columns,
        ),
        'verify',
      );
    });

    test('已在待验证不重复移', () {
      expect(
        targetVerifyColumnIdIfNeeded(
          originalFeedback: const [],
          nextFeedback: [ChecklistItem(id: 'vf1', text: '请验')],
          currentColumnId: 'verify',
          columns: columns,
        ),
        isNull,
      );
    });

    test('仅 checklist 式变更（无新增 VF id）不触发', () {
      // 模拟：打开时已有 VF，本次只改勾选；子任务草稿是否提交与本函数无关。
      expect(
        targetVerifyColumnIdIfNeeded(
          originalFeedback: [
            ChecklistItem(id: 'vf1', text: '旧反馈'),
          ],
          nextFeedback: [
            ChecklistItem(id: 'vf1', text: '旧反馈', completed: true),
          ],
          currentColumnId: 'doing',
          columns: columns,
        ),
        isNull,
      );
    });

    test('无新增 VF（列表未变）不触发', () {
      expect(
        targetVerifyColumnIdIfNeeded(
          originalFeedback: const [],
          nextFeedback: const [],
          currentColumnId: 'doing',
          columns: columns,
        ),
        isNull,
      );
    });
  });
}
