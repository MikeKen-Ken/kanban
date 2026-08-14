/// 单个看板项目的 Agent 调度进度，供总览与工作台展示。
class AgentDispatchProgress {
  const AgentDispatchProgress({
    this.running = false,
    this.processedCards = 0,
    this.totalCards = 0,
    this.currentRound = 0,
  });

  static const idle = AgentDispatchProgress();

  final bool running;
  final int processedCards;
  final int totalCards;
  final int currentRound;

  String get fractionLabel {
    if (totalCards <= 0) return '$processedCards/…';
    return '$processedCards/$totalCards';
  }

  double? get fraction {
    if (!running || totalCards <= 0) return null;
    final value = processedCards / totalCards;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  AgentDispatchProgress copyWith({
    bool? running,
    int? processedCards,
    int? totalCards,
    int? currentRound,
  }) {
    return AgentDispatchProgress(
      running: running ?? this.running,
      processedCards: processedCards ?? this.processedCards,
      totalCards: totalCards ?? this.totalCards,
      currentRound: currentRound ?? this.currentRound,
    );
  }
}

int plannedDispatchTotal({
  required bool cardLimitMax,
  required int cardLimitCount,
  required int queueSize,
}) {
  if (queueSize <= 0) return cardLimitMax ? 0 : cardLimitCount;
  if (cardLimitMax) return queueSize;
  return cardLimitCount < queueSize ? cardLimitCount : queueSize;
}

final _roundPattern = RegExp(r'Worker 单卡轮次 (\d+)/(\d+)');
final _confirmedPattern = RegExp(r'Worker 确认第 (\d+) 次');
final _processedPattern = RegExp(r'已处理 (\d+) 张');

/// 从 Worker 日志行更新进度；无法识别的行原样返回。
AgentDispatchProgress applyWorkerProgressLog(
  AgentDispatchProgress current,
  String message,
) {
  final round = _roundPattern.firstMatch(message);
  if (round != null) {
    return current.copyWith(currentRound: int.parse(round.group(1)!));
  }
  final confirmed = _confirmedPattern.firstMatch(message);
  if (confirmed != null) {
    return _withProcessed(current, int.parse(confirmed.group(1)!));
  }
  final processed = _processedPattern.firstMatch(message);
  if (processed != null) {
    return _withProcessed(current, int.parse(processed.group(1)!));
  }
  return current;
}

AgentDispatchProgress _withProcessed(AgentDispatchProgress current, int processed) {
  final total =
      current.totalCards > processed ? current.totalCards : processed;
  return current.copyWith(processedCards: processed, totalCards: total);
}
