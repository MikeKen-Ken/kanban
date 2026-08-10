import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/mcp_card_payloads.dart';
import 'package:kanban/features/mcp/mcp_tool_results.dart';
import 'package:kanban/features/kanban/kanban_labels.dart';
import 'package:kanban/features/views/card_reference.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main() {
  test('MCP JSON 使用紧凑编码且仍可正常解析', () {
    final result = mcpJsonResult({
      'ok': true,
      'items': [1, 2],
    });
    final text = (result.content.single as TextContent).text;

    expect(text, '{"ok":true,"items":[1,2]}');
    expect(jsonDecode(text), {
      'ok': true,
      'items': [1, 2],
    });
  });

  test('整板紧凑摘要不携带备注和关联详情', () {
    final card = _card();

    final compact = mcpBoardCardSummary(card);
    final detailed = mcpBoardCardSummary(card, includeDetails: true);

    expect(compact['checklist'], {'done': 1, 'total': 1});
    expect(compact['verificationFeedback'], {'done': 0, 'total': 1});
    expect(compact['blockedByIds'], ['before']);
    expect(compact, isNot(contains('description')));
    expect(compact, isNot(contains('relatedIds')));
    expect(compact, isNot(contains('links')));

    expect(detailed['description'], endsWith('…'));
    expect(detailed['relatedIds'], ['related']);
    expect(detailed['links'], hasLength(1));
  });

  test('搜索摘要省略大文本并保留筛选和依赖字段', () {
    final card = _card();
    final reference = _reference(card);

    final summary = mcpCardReferenceSummary(reference);
    final full = mcpCardReferencePayload(reference, full: true);

    expect(summary['cardId'], 'card-1');
    expect(summary['labelIds'], ['needs_verify']);
    expect(summary['checklistCount'], 1);
    expect(summary['verificationFeedbackCount'], 1);
    expect(summary['blockedByIds'], ['before']);
    expect(summary, isNot(contains('description')));
    expect(summary, isNot(contains('checklistTexts')));
    expect(summary, isNot(contains('verificationFeedbackTexts')));
    expect(summary, isNot(contains('links')));
    expect(summary, isNot(contains('relatedIds')));

    expect(full['description'], isNotEmpty);
    expect(full['checklistTexts'], ['子任务正文']);
    expect(full['verificationFeedbackTexts'], ['返工反馈正文']);
    expect(full['links'], hasLength(1));
  });

  test('单卡详情不重复返回清单与反馈的纯文本副本', () {
    final details = mcpCardDetails(_reference(_card()));

    expect(details, isNot(contains('checklistTexts')));
    expect(details, isNot(contains('verificationFeedbackTexts')));
    expect(details['checklist'], [
      {'id': 'check-1', 'text': '子任务正文', 'completed': true},
    ]);
    expect(details['verificationFeedback'], [
      {'id': 'feedback-1', 'text': '返工反馈正文', 'completed': false},
    ]);
  });
}

KanbanCard _card() => KanbanCard(
      id: 'card-1',
      title: '需要处理的任务',
      description: List.filled(80, '说明').join(),
      order: 0,
      createdAt: 1,
      priority: CardPriority.high,
      labels: const ['needs_verify'],
      checklist: [
        ChecklistItem(id: 'check-1', text: '子任务正文', completed: true),
      ],
      verificationFeedback: [
        ChecklistItem(id: 'feedback-1', text: '返工反馈正文'),
      ],
      links: [
        CardLink(
          id: 'link-1',
          url: 'https://example.com/very/long/reference',
          title: '参考资料',
          order: 0,
          createdAt: 1,
        ),
      ],
      blockedByIds: const ['before'],
      relatedIds: const ['related'],
    );

CardReference _reference(KanbanCard card) => CardReference(
      projectId: 'project-1',
      projectName: '项目一',
      columnId: 'todo',
      columnName: '待办',
      cardId: card.id,
      title: card.title,
      description: card.description,
      labelIds: card.labels,
      labelNames: const ['验收'],
      checklistTexts: const ['子任务正文'],
      verificationFeedbackTexts: const ['返工反馈正文'],
      priority: card.priority.name,
      blockedByIds: card.blockedByIds,
      relatedIds: card.relatedIds,
      links: [for (final link in card.links) link.toJson()],
      source: card,
    );
