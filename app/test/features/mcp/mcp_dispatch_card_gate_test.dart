import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/mcp_dispatch_card_gate.dart';

void main() {
  final gate = McpDispatchCardGate.instance;

  setUp(gate.debugReset);
  tearDown(gate.debugReset);

  test('Worker 每次开启新会话后只允许 Skill 取一张卡', () {
    gate.beginBatch('worker-a', projectId: 'project-a');

    expect(
      gate.authorizePick('project-a'),
      McpDispatchPickPermission.sessionNotOpen,
    );
    expect(gate.beginAgentSession('worker-b'), isFalse);
    expect(gate.beginAgentSession('worker-a'), isTrue);
    expect(gate.authorizePick('project-a'), McpDispatchPickPermission.allowed);
    expect(
      gate.authorizePick('project-a'),
      McpDispatchPickPermission.alreadyClaimed,
    );

    gate.recordPickedCard(projectId: 'project-a', cardId: 'card-a');
    final status = gate.sessionStatus('worker-a');
    expect(status?.pickClaimed, isTrue);
    expect(status?.deniedPickCount, 1);
    expect(status?.cardId, 'card-a');
    expect(gate.authorizePickedCard('card-a'), isNull);
    expect(gate.authorizePickedCard('other'), isNotNull);

    expect(gate.beginAgentSession('worker-a'), isTrue);
    expect(gate.authorizePick('project-a'), McpDispatchPickPermission.allowed);
  });

  test('没有 Worker 批次时不影响普通 MCP 取卡', () {
    expect(gate.authorizePick('project-a'), McpDispatchPickPermission.allowed);
  });

  test('不同项目的批次互不影响领卡次数', () {
    gate.beginBatch('worker-a', projectId: 'project-a');
    gate.beginBatch('worker-b', projectId: 'project-b');
    expect(gate.beginAgentSession('worker-a'), isTrue);
    expect(gate.beginAgentSession('worker-b'), isTrue);

    expect(gate.authorizePick('project-a'), McpDispatchPickPermission.allowed);
    expect(gate.authorizePick('project-b'), McpDispatchPickPermission.allowed);
    expect(
      gate.authorizePick('project-a'),
      McpDispatchPickPermission.alreadyClaimed,
    );
    expect(
      gate.sessionStatus('worker-b')?.pickClaimed,
      isFalse,
    );
    gate.recordPickedCard(projectId: 'project-b', cardId: 'card-b');
    expect(gate.sessionStatus('worker-b')?.pickClaimed, isTrue);
    expect(gate.openSessionCount, 2);
    expect(gate.singleOpenSessionProjectId, isNull);
  });

  test('批次可绑定仓库路径并记录待提交号', () {
    gate.beginBatch(
      'worker-a',
      projectId: 'project-a',
      repoPath: r'D:\repo',
    );
    expect(gate.beginAgentSession('worker-a'), isTrue);
    expect(
      gate.authorizePick('project-a'),
      McpDispatchPickPermission.allowed,
    );
    expect(gate.authorizePickedCard('card-a'), isNotNull);
    gate.recordPickedCard(projectId: 'project-a', cardId: 'card-a');
    expect(gate.repoPathForPickedCard('card-a'), r'D:\repo');
    gate.recordPendingCommitRef(cardId: 'card-a', commitRef: 'abc1234');
    expect(gate.pendingCommitRefForCard('card-a'), 'abc1234');
    expect(gate.authorizePickedCard('card-a'), isNull);
    expect(gate.authorizePickedCard('missing'), isNotNull);
  });

  test('仅一轮会话开启时可以推断项目', () {
    gate.beginBatch('worker-a', projectId: 'project-a');
    expect(gate.beginAgentSession('worker-a'), isTrue);
    expect(gate.singleOpenSessionProjectId, 'project-a');
    expect(gate.openSessionCount, 1);
  });

  test('领卡失败后可以在同一会话重试', () {
    gate.beginBatch('worker-a', projectId: 'project-a');
    expect(gate.beginAgentSession('worker-a'), isTrue);
    expect(gate.authorizePick('project-a'), McpDispatchPickPermission.allowed);
    gate.releasePickAttempt('project-a');
    expect(gate.authorizePick('project-a'), McpDispatchPickPermission.allowed);
    gate.recordPickedCard(projectId: 'project-a', cardId: 'card-a');
    expect(
      gate.authorizePick('project-a'),
      McpDispatchPickPermission.alreadyClaimed,
    );
  });
}
