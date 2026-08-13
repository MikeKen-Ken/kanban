import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_config.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_session.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_worker.dart';

void main() {
  test('固定张数按张数串行，Max 有会话上限', () {
    expect(dispatchSessionLimit(AgentDispatchCardLimit.count(3)), 3);
    expect(dispatchSessionLimit(AgentDispatchCardLimit.max), 999);
  });

  test('识别无卡标记后停止', () {
    const result = AgentWorkerResult(ok: true, summary: 'KANBAN_DISPATCH:NO_CARD');
    expect(
      dispatchSessionHasNoCard(result: result, sessionLog: ''),
      isTrue,
    );
    expect(
      shouldContinueDispatch(
        cardLimit: AgentDispatchCardLimit.max,
        finishedSessions: 1,
        lastResult: result,
        sessionLog: '',
        cancelRequested: false,
      ),
      isFalse,
    );
  });

  test('成功处理一张后继续直到上限', () {
    const result = AgentWorkerResult(
      ok: true,
      summary: 'KANBAN_DISPATCH:CARD_DONE',
    );
    expect(
      shouldContinueDispatch(
        cardLimit: AgentDispatchCardLimit.count(2),
        finishedSessions: 1,
        lastResult: result,
        sessionLog: '',
        cancelRequested: false,
      ),
      isTrue,
    );
    expect(
      shouldContinueDispatch(
        cardLimit: AgentDispatchCardLimit.count(2),
        finishedSessions: 2,
        lastResult: result,
        sessionLog: '',
        cancelRequested: false,
      ),
      isFalse,
    );
  });
}
