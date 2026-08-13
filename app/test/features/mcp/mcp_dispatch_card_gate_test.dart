import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/mcp_dispatch_card_gate.dart';

void main() {
  test('Worker 每次开启新会话后只允许 Skill 取一张卡', () {
    final gate = McpDispatchCardGate.instance;
    gate.beginBatch('worker-a');
    addTearDown(() => gate.endBatch('worker-a'));

    expect(
      gate.authorizePick(),
      McpDispatchPickPermission.sessionNotOpen,
    );
    expect(gate.beginAgentSession('worker-b'), isFalse);
    expect(gate.beginAgentSession('worker-a'), isTrue);
    expect(gate.authorizePick(), McpDispatchPickPermission.allowed);
    expect(
      gate.authorizePick(),
      McpDispatchPickPermission.alreadyClaimed,
    );

    gate.recordPickedCard(projectId: 'project-a', cardId: 'card-a');
    final status = gate.sessionStatus('worker-a');
    expect(status?.pickClaimed, isTrue);
    expect(status?.deniedPickCount, 1);
    expect(status?.cardId, 'card-a');

    expect(gate.beginAgentSession('worker-a'), isTrue);
    expect(gate.authorizePick(), McpDispatchPickPermission.allowed);
  });

  test('没有 Worker 批次时不影响普通 MCP 取卡', () {
    final gate = McpDispatchCardGate.instance;
    final token = gate.activeWorkerToken;
    if (token != null) gate.endBatch(token);
    expect(gate.authorizePick(), McpDispatchPickPermission.allowed);
  });
}
