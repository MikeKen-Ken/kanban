import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/mcp_dispatch_card_gate.dart';
import 'package:kanban/features/mcp/mcp_tools_agent_session.dart';

void main() {
  final gate = McpDispatchCardGate.instance;

  setUp(gate.debugReset);
  tearDown(gate.debugReset);

  test('Agent 会话只暴露三个 scoped 工具', () {
    expect(kanbanMcpAgentSessionToolNames, [
      'ready_to_submit',
      'submit_consultation',
      'block_card',
    ]);
  });

  test('scoped 会话按 workerToken 与 cardId 双重绑定', () {
    gate.beginBatch('worker-a', projectId: 'project-a');
    expect(
      gate.beginAgentSession('worker-a', sessionId: 'session-a'),
      isTrue,
    );
    expect(
      gate.authorizePick('project-a', workerToken: 'worker-a'),
      McpDispatchPickPermission.allowed,
    );
    gate.recordPickedCard(
      projectId: 'project-a',
      cardId: 'card-a',
      workerToken: 'worker-a',
    );

    expect(
      gate.authorizeScopedCard(
        workerToken: 'worker-a',
        cardId: 'card-a',
      ),
      isNull,
    );
    expect(
      gate.authorizeScopedCard(workerToken: 'worker-a', cardId: 'other'),
      isNotNull,
    );
  });
}
