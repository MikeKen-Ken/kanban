import 'agent_dispatch_config.dart';
import 'agent_dispatch_worker.dart';

const kDispatchCardDoneMarker = 'KANBAN_DISPATCH:CARD_DONE';
const kDispatchNoCardMarker = 'KANBAN_DISPATCH:NO_CARD';
const kDispatchMaxSessions = 999;

/// 每张卡片单独开一次会话，避免多卡并行改同一处。
int dispatchSessionLimit(AgentDispatchCardLimit cardLimit) {
  return switch (cardLimit) {
    AgentDispatchCardLimitMax() => kDispatchMaxSessions,
    AgentDispatchCardLimitCount(:final count) => count.clamp(1, 999),
  };
}

bool dispatchSessionHasNoCard({
  required AgentWorkerResult result,
  required String sessionLog,
}) {
  final text = '${result.summary ?? ''}\n${result.error ?? ''}\n$sessionLog';
  return text.contains(kDispatchNoCardMarker);
}

bool shouldContinueDispatch({
  required AgentDispatchCardLimit cardLimit,
  required int finishedSessions,
  required AgentWorkerResult lastResult,
  required String sessionLog,
  required bool cancelRequested,
}) {
  if (cancelRequested || !lastResult.ok) return false;
  if (dispatchSessionHasNoCard(result: lastResult, sessionLog: sessionLog)) {
    return false;
  }
  final limit = dispatchSessionLimit(cardLimit);
  return finishedSessions < limit;
}
