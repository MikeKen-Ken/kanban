import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_interaction.dart';
import 'package:kanban/features/sync_conflict/card_merge.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  test('解析 Worker 提问并生成 Markdown 对话', () {
    final event = parseAgentInteractionEvent(
      '@@KANBAN_INTERACTION@@'
      '{"type":"question","cardId":"card-a","sessionId":"session-a",'
      '"requestId":"request-a","text":"请选择方案","at":"2026-08-19T08:00:00Z"}',
    );

    expect(event, isNotNull);
    expect(event!.awaitsReply, isTrue);
    expect(event.requestId, 'request-a');
    final markdown = appendAgentConversationEvent(null, event);
    expect(markdown, contains('### 助手'));
    expect(markdown, contains('请选择方案'));
    expect(
      appendAgentConversationUserReply(markdown, '使用方案 A'),
      contains('### 用户\n使用方案 A'),
    );
  });

  test('可从日志前缀后解析交互事件', () {
    final event = parseAgentInteractionEvent(
      '[ai] @@KANBAN_INTERACTION@@'
      '{"type":"assistant","cardId":"card-a","sessionId":"session-a",'
      '"text":"完整答复","at":"2026-08-19T08:00:00Z"}',
    );
    expect(event, isNotNull);
    expect(event!.text, '完整答复');
  });

  test('流式变长的助手正文会合并为完整一段', () {
    final first = parseAgentInteractionEvent(
      '@@KANBAN_INTERACTION@@'
      '{"type":"assistant","cardId":"card-a","sessionId":"session-a",'
      '"text":"先改保存。","at":"2026-08-19T08:00:00Z"}',
    )!;
    final second = parseAgentInteractionEvent(
      '@@KANBAN_INTERACTION@@'
      '{"type":"assistant","cardId":"card-a","sessionId":"session-a",'
      '"text":"先改保存。再补上完整助手消息。","at":"2026-08-19T08:00:01Z"}',
    )!;
    final markdown = appendAgentConversationEvent(
      appendAgentConversationEvent(null, first),
      second,
    );
    expect(markdown, contains('先改保存。再补上完整助手消息。'));
    expect('### 助手'.allMatches(markdown).length, 1);
  });

  test('卡片对话字段可序列化并兼容旧数据缺省', () {
    final card = _card(
      conversation: '## 会话\n\n### 用户\n继续处理\n',
    );
    final restored = KanbanCard.fromJson(card.toJson());
    expect(restored.agentConversationMarkdown, card.agentConversationMarkdown);

    final oldJson = card.toJson()..remove('agentConversationMarkdown');
    expect(KanbanCard.fromJson(oldJson).agentConversationMarkdown, isNull);
  });

  test('三路合并可自动采用单侧新增的对话', () {
    final base = _card();
    final local = _card(conversation: '### 用户\n补充约束\n', updatedAt: 2);
    final result = mergeCardThreeWay(
      base: PlacedCard(card: base, columnId: 'todo'),
      local: PlacedCard(card: local, columnId: 'todo'),
      remote: PlacedCard(card: base, columnId: 'todo'),
    );

    expect(
      result.placed?.card.agentConversationMarkdown,
      '### 用户\n补充约束\n',
    );
    expect(result.placed?.card.hasConflict, isFalse);
  });
}

KanbanCard _card({
  String? conversation,
  int updatedAt = 1,
}) {
  return KanbanCard(
    id: 'card-a',
    title: '任务',
    order: 0,
    createdAt: 1,
    updatedAt: updatedAt,
    agentConversationMarkdown: conversation,
  );
}
