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

  group('hasIncompleteVerificationFeedback', () {
    test('存在未勾选项为 true', () {
      expect(
        hasIncompleteVerificationFeedback([
          ChecklistItem(id: 'a', text: '已改', completed: true),
          ChecklistItem(id: 'b', text: '未改'),
        ]),
        isTrue,
      );
    });

    test('全部勾选或空列表为 false', () {
      expect(hasIncompleteVerificationFeedback(const []), isFalse);
      expect(
        hasIncompleteVerificationFeedback([
          ChecklistItem(id: 'a', text: 'ok', completed: true),
        ]),
        isFalse,
      );
    });
  });

  group('targetReworkColumnIdIfIncompleteFeedback', () {
    final columns = [
      KanbanColumn(id: 'verify', title: '待验证', order: 0, cards: const []),
      KanbanColumn(
        id: KanbanBoard.defaultReworkColumnId,
        title: KanbanBoard.defaultReworkColumnTitle,
        order: 1,
        cards: const [],
      ),
      KanbanColumn(id: 'done', title: '已完成', order: 2, cards: const []),
    ];

    test('有未完成 VF 且不在待返工 → 返回待返工列 id', () {
      expect(
        targetReworkColumnIdIfIncompleteFeedback(
          feedback: [ChecklistItem(id: 'vf1', text: '请返工')],
          currentColumnId: 'verify',
          columns: columns,
        ),
        'rework',
      );
    });

    test('已在待返工不重复移', () {
      expect(
        targetReworkColumnIdIfIncompleteFeedback(
          feedback: [ChecklistItem(id: 'vf1', text: '请返工')],
          currentColumnId: 'rework',
          columns: columns,
        ),
        isNull,
      );
    });

    test('全部已完成不触发', () {
      expect(
        targetReworkColumnIdIfIncompleteFeedback(
          feedback: [
            ChecklistItem(id: 'vf1', text: '已修', completed: true),
          ],
          currentColumnId: 'verify',
          columns: columns,
        ),
        isNull,
      );
    });
  });

  group('shouldPreferReworkOverComplete', () {
    test('新增未完成 VF 时优先待返工', () {
      expect(
        shouldPreferReworkOverComplete(
          nextFeedback: [ChecklistItem(id: 'n', text: '新问题')],
        ),
        isTrue,
      );
    });

    test('仍有未完成 VF 时优先待返工（即使未新增）', () {
      expect(
        shouldPreferReworkOverComplete(
          nextFeedback: [
            ChecklistItem(id: 'old', text: '旧反馈'),
          ],
        ),
        isTrue,
      );
    });

    test('无未完成 VF 时可走已完成', () {
      expect(
        shouldPreferReworkOverComplete(nextFeedback: const []),
        isFalse,
      );
      expect(
        shouldPreferReworkOverComplete(
          nextFeedback: [
            ChecklistItem(id: 'a', text: '已闭环', completed: true),
          ],
        ),
        isFalse,
      );
    });
  });
}
