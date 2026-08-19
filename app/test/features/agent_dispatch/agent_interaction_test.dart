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

  test('会话快照会写入用户与全部助手消息', () {
    final session = parseAgentInteractionEvent(
      '@@KANBAN_INTERACTION@@'
      '{"type":"session","cardId":"card-a","sessionId":"session-a",'
      '"text":"- 标题","at":"2026-08-19T08:00:00Z"}',
    )!;
    final first = parseAgentInteractionEvent(
      '@@KANBAN_INTERACTION@@'
      '{"type":"assistant","cardId":"card-a","sessionId":"session-a",'
      '"text":"短句","at":"2026-08-19T08:00:01Z"}',
    )!;
    final snapshot = parseAgentInteractionEvent(
      '@@KANBAN_INTERACTION@@'
      '{"type":"snapshot","cardId":"card-a","sessionId":"session-a",'
      '"text":"[{\\"role\\":\\"user\\",\\"text\\":\\"- 标题\\"},'
      '{\\"role\\":\\"assistant\\",\\"text\\":\\"第一条完整助手。\\"},'
      '{\\"role\\":\\"assistant\\",\\"text\\":\\"第二条完整助手。\\"}]",'
      '"at":"2026-08-19T08:00:02Z"}',
    )!;
    final markdown = appendAgentConversationEvent(
      appendAgentConversationEvent(
        appendAgentConversationEvent(null, session),
        first,
      ),
      snapshot,
    );
    expect(markdown, contains('### 用户\n- 标题'));
    expect(markdown, contains('### 助手\n第一条完整助手。'));
    expect(markdown, contains('### 助手\n第二条完整助手。'));
    expect(markdown, isNot(contains('短句')));
    expect('### 助手'.allMatches(markdown).length, 2);
  });

  test('二次追问快照追加新会话，不覆盖第一次记录', () {
    const first = '## 会话 2026-08-19 08:00\n\n'
        '### 用户\n'
        '- 第一次任务\n\n'
        '### 助手\n'
        '第一次完整答复。\n\n'
        '### 用户\n'
        '请再确认窗口默认关闭\n';
    final snapshot = parseAgentInteractionEvent(
      '@@KANBAN_INTERACTION@@'
      '{"type":"snapshot","cardId":"card-a","sessionId":"session-b",'
      '"text":"[{\\"role\\":\\"user\\",\\"text\\":\\"- Agent 追问：请再确认窗口默认关闭\\"},'
      '{\\"role\\":\\"assistant\\",\\"text\\":\\"第二次答复。\\"}]",'
      '"at":"2026-08-19T10:00:00Z"}',
    )!;
    final markdown = appendAgentConversationEvent(first, snapshot);
    expect(markdown, contains('第一次完整答复。'));
    expect(markdown, contains('请再确认窗口默认关闭'));
    expect(markdown, contains('第二次答复。'));
    expect('## 会话'.allMatches(markdown).length, 2);
  });

  test('无会话标题时快照也追加而不是整文件覆盖', () {
    const first = '### 用户\n第一次任务\n\n### 助手\n第一次答复。\n';
    final markdown = replaceAgentConversationSession(first, const [
      AgentConversationMessage(role: 'user', text: '第二次追问'),
      AgentConversationMessage(role: 'assistant', text: '第二次答复。'),
    ], at: DateTime.utc(2026, 8, 19, 10));
    expect(markdown, contains('第一次答复。'));
    expect(markdown, contains('第二次答复。'));
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
