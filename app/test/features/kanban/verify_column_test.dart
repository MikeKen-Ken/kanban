import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/verify_column.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
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
      KanbanColumn(id: 'done', title: '已完成', order: 2, cards: const []),
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

    test('非待验证列不默认预览', () {
      expect(
        shouldDefaultPreviewMarkdown(columnId: 'todo', columns: columns),
        isFalse,
      );
      expect(
        shouldDefaultPreviewMarkdown(columnId: 'done', columns: columns),
        isFalse,
      );
    });

    test('列快照缺失时仍识别默认 id verify', () {
      expect(
        isVerifyColumnId(columnId: 'verify', columns: const []),
        isTrue,
      );
    });
  });
}
