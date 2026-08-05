import 'package:flutter_test/flutter_test.dart';

import 'package:kanban/features/automations/automations.dart';
import 'package:kanban/features/kanban/kanban_labels.dart';
import 'package:kanban/features/kanban/swimlane.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  group('SwimlaneService', () {
    const service = SwimlaneService();

    test('按优先级分组', () {
      final cards = [
        KanbanCard(
          id: '1',
          title: '高',
          order: 0,
          createdAt: 1,
          priority: CardPriority.high,
        ),
        KanbanCard(
          id: '2',
          title: '无',
          order: 1,
          createdAt: 1,
        ),
      ];
      final buckets = service.bucketsFor(
        mode: SwimlaneMode.priority,
        cards: cards,
      );
      expect(buckets.length, 4);
      expect(
        service.cardMatches(cards.first, buckets.first, SwimlaneMode.priority),
        isTrue,
      );
      final updated = service.applyBucket(
        cards[1],
        buckets.first,
        SwimlaneMode.priority,
      );
      expect(updated.priority, CardPriority.high);
    });
  });

  group('AutomationEngine', () {
    const engine = AutomationEngine();

    test('移入指定列可标记完成', () {
      final card = KanbanCard(
        id: 'c1',
        title: '任务',
        order: 0,
        createdAt: 1,
      );
      final effects = engine.effectsForMove(
        rules: [
          const AutomationRule(
            id: 'r1',
            name: '完成',
            trigger: AutomationTrigger.movedToColumn,
            triggerColumnId: 'done',
            action: AutomationActionType.markCompleted,
          ),
        ],
        toColumnId: 'done',
        card: card,
      );
      expect(effects, hasLength(1));
      expect(effects.first.completed, isTrue);
    });

    test('清单全部完成后可加标签', () {
      final card = KanbanCard(
        id: 'c1',
        title: '任务',
        order: 0,
        createdAt: 1,
        checklist: [
          ChecklistItem(id: 'i1', text: 'a', completed: true),
          ChecklistItem(id: 'i2', text: 'b', completed: true),
        ],
      );
      final effects = engine.effectsForChecklistAllDone(
        rules: [
          const AutomationRule(
            id: 'r1',
            name: '加标签',
            trigger: AutomationTrigger.checklistAllDone,
            action: AutomationActionType.addLabel,
            actionLabelKey: 'urgent',
          ),
        ],
        card: card,
      );
      expect(effects.single.addLabelKey, 'urgent');
    });
  });

  group('CardLink / relations json', () {
    test('往返序列化保留新字段', () {
      final card = KanbanCard(
        id: 'c1',
        title: '任务',
        order: 0,
        createdAt: 1,
        links: [
          CardLink(
            id: 'l1',
            url: 'https://example.com',
            title: '示例',
            order: 0,
            createdAt: 1,
          ),
        ],
        blockedByIds: const ['a'],
        relatedIds: const ['b'],
      );
      final restored = KanbanCard.fromJson(card.toJson());
      expect(restored.links.single.url, 'https://example.com');
      expect(restored.blockedByIds, ['a']);
      expect(restored.relatedIds, ['b']);
    });
  });
}
