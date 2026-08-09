import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/completed_auto_clear/completed_auto_clear.dart';
import 'package:kanban/features/kanban/move_to_rework_on_new_feedback.dart';
import 'package:kanban/features/kanban/swimlane.dart';
import 'package:kanban/features/kanban/verify_column.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  test('泳道顶栏按钮按优先级、按标签、关闭的顺序循环', () {
    expect(nextSwimlaneMode(SwimlaneMode.none), SwimlaneMode.priority);
    expect(nextSwimlaneMode(SwimlaneMode.priority), SwimlaneMode.label);
    expect(nextSwimlaneMode(SwimlaneMode.label), SwimlaneMode.none);
  });
  group('findVerifyColumn', () {
    test('按标题解析，列 id 可自定义', () {
      final col = KanbanColumn(
        id: 'db12a167-6019-4ea5-9af2-582e359a68a1',
        title: '待验证',
        order: 0,
        cards: const [],
      );
      expect(findVerifyColumn([col])?.id, col.id);
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

  group('isVerifyColumnId / shouldDefaultPreviewMarkdown', () {
    final columns = [
      KanbanColumn(id: 'todo', title: '待办', order: 0, cards: const []),
      KanbanColumn(
        id: 'custom-verify',
        title: KanbanBoard.defaultVerifyColumnTitle,
        order: 1,
        cards: const [],
      ),
      KanbanColumn(
        id: 'custom-rework',
        title: KanbanBoard.defaultReworkColumnTitle,
        order: 2,
        cards: const [],
      ),
      KanbanColumn(
        id: 'custom-done',
        title: '已完成',
        order: 3,
        cards: const [],
      ),
    ];

    test('自定义 id 的待验证列为 true', () {
      expect(
        isVerifyColumnId(columnId: 'custom-verify', columns: columns),
        isTrue,
      );
      expect(
        shouldDefaultPreviewMarkdown(
          columnId: 'custom-verify',
          columns: columns,
        ),
        isTrue,
      );
    });

    test('待返工与已完成列默认预览', () {
      expect(
        isReworkColumnId(columnId: 'custom-rework', columns: columns),
        isTrue,
      );
      expect(
        shouldDefaultPreviewMarkdown(
          columnId: 'custom-rework',
          columns: columns,
        ),
        isTrue,
      );
      expect(
        isDoneColumnId(
          columnId: 'custom-done',
          columns: columns,
          doneColumnName: '已完成',
        ),
        isTrue,
      );
      expect(
        shouldDefaultPreviewMarkdown(
          columnId: 'custom-done',
          columns: columns,
          doneColumnName: '已完成',
        ),
        isTrue,
      );
    });

    test('默认 id 的待返工与已完成在快照中也默认预览', () {
      final defaultRoleColumns = [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: const []),
        KanbanColumn(id: 'verify', title: '待验证', order: 1, cards: const []),
        KanbanColumn(id: 'rework', title: '待返工', order: 2, cards: const []),
        KanbanColumn(id: 'done', title: '已完成', order: 3, cards: const []),
      ];
      expect(
        shouldDefaultPreviewMarkdown(
          columnId: 'rework',
          columns: defaultRoleColumns,
        ),
        isTrue,
      );
      expect(
        shouldDefaultPreviewMarkdown(
          columnId: 'done',
          columns: defaultRoleColumns,
        ),
        isTrue,
      );
    });

    test('非角色列不默认预览', () {
      expect(
        shouldDefaultPreviewMarkdown(columnId: 'todo', columns: columns),
        isFalse,
      );
      expect(
        shouldDefaultPreviewMarkdown(
          columnId: 'doing',
          columns: [
            KanbanColumn(id: 'doing', title: '进行中', order: 0, cards: const []),
          ],
        ),
        isFalse,
      );
    });

    test('列快照缺失时仍识别默认 id', () {
      expect(
        isVerifyColumnId(columnId: 'verify', columns: const []),
        isTrue,
      );
      expect(
        shouldDefaultPreviewMarkdown(columnId: 'verify', columns: const []),
        isTrue,
      );
      expect(
        shouldDefaultPreviewMarkdown(columnId: 'rework', columns: const []),
        isTrue,
      );
      expect(
        shouldDefaultPreviewMarkdown(columnId: 'done', columns: const []),
        isTrue,
      );
    });

    test('自定义已完成列名仍按角色识别', () {
      final renamed = [
        KanbanColumn(id: 'todo', title: '待办', order: 0, cards: const []),
        KanbanColumn(id: 'archive', title: '完成归档', order: 1, cards: const []),
      ];
      expect(
        shouldDefaultPreviewMarkdown(
          columnId: 'archive',
          columns: renamed,
          doneColumnName: '完成归档',
        ),
        isTrue,
      );
      expect(
        shouldDefaultPreviewMarkdown(
          columnId: 'todo',
          columns: renamed,
          doneColumnName: '完成归档',
        ),
        isFalse,
      );
    });
  });
}
