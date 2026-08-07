import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/move_to_rework_on_new_feedback.dart';
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

  group('findReworkColumn', () {
    test('按标题解析，列 id 可自定义', () {
      final col = KanbanColumn(
        id: 'col-xyz',
        title: '待返工',
        order: 0,
        cards: const [],
      );
      expect(findReworkColumn([col])?.id, 'col-xyz');
    });

    test('标题不符时回退默认 id rework', () {
      final col = KanbanColumn(
        id: KanbanBoard.defaultReworkColumnId,
        title: '返工中',
        order: 0,
        cards: const [],
      );
      expect(findReworkColumn([col])?.id, 'rework');
    });

    test('找不到返回 null', () {
      expect(
        findReworkColumn([
          KanbanColumn(id: 'todo', title: '待办', order: 0, cards: const []),
        ]),
        isNull,
      );
    });
  });

  group('targetReworkColumnIdIfNeeded', () {
    final columns = [
      KanbanColumn(id: 'doing', title: '进行中', order: 0, cards: const []),
      KanbanColumn(
        id: KanbanBoard.defaultReworkColumnId,
        title: KanbanBoard.defaultReworkColumnTitle,
        order: 1,
        cards: const [],
      ),
    ];

    test('新增 VF 且不在待返工 → 返回待返工列 id', () {
      expect(
        targetReworkColumnIdIfNeeded(
          originalFeedback: const [],
          nextFeedback: [ChecklistItem(id: 'vf1', text: '请验')],
          currentColumnId: 'doing',
          columns: columns,
        ),
        'rework',
      );
    });

    test('已在待返工不重复移', () {
      expect(
        targetReworkColumnIdIfNeeded(
          originalFeedback: const [],
          nextFeedback: [ChecklistItem(id: 'vf1', text: '请验')],
          currentColumnId: 'rework',
          columns: columns,
        ),
        isNull,
      );
    });

    test('仅 checklist 式变更（无新增 VF id）不触发', () {
      // 模拟：打开时已有 VF，本次只改勾选；子任务草稿是否提交与本函数无关。
      expect(
        targetReworkColumnIdIfNeeded(
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
        targetReworkColumnIdIfNeeded(
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
