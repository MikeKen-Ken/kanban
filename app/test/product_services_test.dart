import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/activity/activity_models.dart';
import 'package:kanban/features/kanban/kanban_labels.dart';
import 'package:kanban/features/templates/card_template.dart';
import 'package:kanban/features/undo/undo_stack.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  test('活动日志按标识去重并按时间倒序', () {
    ActivityEvent event(String id, int at) => ActivityEvent(
          id: id,
          projectId: 'p1',
          entityType: 'card',
          entityId: id,
          entityTitle: id,
          action: ActivityAction.updated,
          occurredAt: at,
        );

    final merged = ActivityLog(events: [event('a', 1), event('b', 2)])
        .mergeWith(ActivityLog(events: [event('a', 1), event('c', 3)]));

    expect(merged.events.map((item) => item.id), ['c', 'b', 'a']);
  });

  test('卡片模板不会复制附件并会重置子任务', () {
    final source = KanbanCard(
      id: 'source',
      title: '发布版本',
      order: 0,
      createdAt: 1,
      priority: CardPriority.high,
      checklist: [
        ChecklistItem(id: 'old', text: '冒烟测试', completed: true),
      ],
      attachments: [
        CardAttachment(
          id: 'image',
          fileName: 'image.jpg',
          mimeType: 'image/jpeg',
          order: 0,
          createdAt: 1,
        ),
      ],
    );
    final template = CardTemplate.fromCard(
      id: 'template',
      name: '发布',
      card: source,
      updatedAt: 2,
    );
    final created = template.createCard(
      cardId: 'new',
      createdAt: 3,
      checklistIds: ['new-item'],
    );

    expect(created.attachments, isEmpty);
    expect(created.checklist.single.id, 'new-item');
    expect(created.checklist.single.completed, isFalse);
  });

  test('撤销栈遵守容量并执行最近动作', () async {
    final values = <int>[];
    final stack = UndoStack(capacity: 2)
      ..push(
        UndoEntry(
          label: '一',
          undo: () async => values.add(1),
          redo: () async => values.add(-1),
        ),
      )
      ..push(
        UndoEntry(
          label: '二',
          undo: () async => values.add(2),
          redo: () async => values.add(-2),
        ),
      )
      ..push(
        UndoEntry(
          label: '三',
          undo: () async => values.add(3),
          redo: () async => values.add(-3),
        ),
      );

    expect(await stack.undo(), isTrue);
    expect(await stack.undo(), isTrue);
    expect(await stack.undo(), isFalse);
    expect(values, [3, 2]);
  });

  test('撤销后可重做，新操作会清空重做栈', () async {
    final values = <String>[];
    final stack = UndoStack()
      ..push(
        UndoEntry(
          label: '甲',
          undo: () async => values.add('undo-甲'),
          redo: () async => values.add('redo-甲'),
        ),
      )
      ..push(
        UndoEntry(
          label: '乙',
          undo: () async => values.add('undo-乙'),
          redo: () async => values.add('redo-乙'),
        ),
      );

    expect(stack.canRedo, isFalse);
    expect(await stack.undo(), isTrue);
    expect(stack.canRedo, isTrue);
    expect(stack.nextRedoLabel, '乙');
    expect(await stack.redo(), isTrue);
    expect(stack.canRedo, isFalse);
    expect(await stack.undo(), isTrue);

    stack.push(
      UndoEntry(
        label: '丙',
        undo: () async => values.add('undo-丙'),
        redo: () async => values.add('redo-丙'),
      ),
    );
    expect(stack.canRedo, isFalse);
    expect(await stack.redo(), isFalse);
    expect(values, ['undo-乙', 'redo-乙', 'undo-乙']);
  });
}
