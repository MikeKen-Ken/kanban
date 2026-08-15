import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/mcp_dispatch_card_gate.dart';
import 'package:kanban/features/mcp/mcp_tools_agent_session.dart';

void main() {
  final gate = McpDispatchCardGate.instance;

  setUp(gate.debugReset);
  tearDown(gate.debugReset);

  test('Skill 会话只暴露四个工具', () {
    expect(kanbanMcpAgentSessionToolNames, [
      'pick_next_card',
      'submit_consultation',
      'commit_and_submit_card',
      'block_card',
    ]);
  });

  test('调度中拒绝操作非本轮领取的卡片', () {
    gate.beginBatch('worker-a', projectId: 'project-a');
    expect(gate.beginAgentSession('worker-a'), isTrue);
    expect(gate.authorizePick('project-a'), McpDispatchPickPermission.allowed);
    gate.recordPickedCard(projectId: 'project-a', cardId: 'card-a');

    expect(mcpRejectForeignDispatchCard('card-a'), isNull);
    expect(mcpRejectForeignDispatchCard('other')?.isError, isTrue);
  });
}
