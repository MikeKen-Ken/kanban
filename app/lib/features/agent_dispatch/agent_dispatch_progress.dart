/// 单个看板项目的 Agent 调度进度，供总览与工作台展示。
class AgentDispatchProgress {
  const AgentDispatchProgress({
    this.running = false,
    this.processedCards = 0,
    this.totalCards = 0,
    this.currentRound = 0,
    this.cardLimitMax = false,
    this.cardLimitCount = 0,
    this.currentTitle = '',
    this.currentDetail = '',
    this.phaseLabel = '',
    this.drainAfterCurrent = false,
  });

  static const idle = AgentDispatchProgress();

  final bool running;
  final int processedCards;
  final int totalCards;
  final int currentRound;
  final bool cardLimitMax;
  final int cardLimitCount;
  final String currentTitle;
  final String currentDetail;
  final String phaseLabel;

  /// 当前会话后停止或立即停止后，不再把队列剩余计入分母。
  final bool drainAfterCurrent;

  String get fractionLabel {
    if (totalCards <= 0) return '$processedCards/…';
    return '$processedCards/$totalCards';
  }

  /// 工作台展示「当前第几张 / 计划总数」，进行中时用轮次而不是已完成数。
  String get liveCardLabel {
    if (!running) return fractionLabel;
    final current = _liveCurrentIndex;
    final total = _liveDenominator;
    if (total <= 0) return '$current/…';
    return '$current/$total';
  }

  int get _liveCurrentIndex =>
      currentRound > 0 ? currentRound : processedCards + 1;

  /// 进行中分母不得低于当前张序号，避免总览出现 4/2。
  int get _liveDenominator {
    if (totalCards <= 0) return totalCards;
    if (!running) return totalCards;
    final floor = _liveCurrentIndex;
    return totalCards < floor ? floor : totalCards;
  }

  double? get fraction {
    final total = _liveDenominator;
    if (!running || total <= 0) return null;
    final completed =
        currentRound > processedCards ? currentRound - 1 : processedCards;
    final value = completed / total;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  AgentDispatchProgress copyWith({
    bool? running,
    int? processedCards,
    int? totalCards,
    int? currentRound,
    bool? cardLimitMax,
    int? cardLimitCount,
    String? currentTitle,
    String? currentDetail,
    String? phaseLabel,
    bool? drainAfterCurrent,
  }) {
    return AgentDispatchProgress(
      running: running ?? this.running,
      processedCards: processedCards ?? this.processedCards,
      totalCards: totalCards ?? this.totalCards,
      currentRound: currentRound ?? this.currentRound,
      cardLimitMax: cardLimitMax ?? this.cardLimitMax,
      cardLimitCount: cardLimitCount ?? this.cardLimitCount,
      currentTitle: currentTitle ?? this.currentTitle,
      currentDetail: currentDetail ?? this.currentDetail,
      phaseLabel: phaseLabel ?? this.phaseLabel,
      drainAfterCurrent: drainAfterCurrent ?? this.drainAfterCurrent,
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

/// 进行中当前张序号（1-based），供分母下限与展示共用。
int dispatchProgressFloor({
  required int processedCards,
  required int currentRound,
  required bool hasActiveCard,
}) {
  final fromRound = currentRound > 0 ? currentRound : 0;
  final fromProcessed = processedCards + (hasActiveCard ? 1 : 0);
  return fromRound > fromProcessed ? fromRound : fromProcessed;
}

/// 已处理张数 + 队列剩余 + 进行中的当前卡，再套用启动时的上限规则。
int liveDispatchTotal({
  required bool cardLimitMax,
  required int cardLimitCount,
  required int processedCards,
  required int remainingQueue,
  required bool hasActiveCard,
  int currentRound = 0,
  bool drainAfterCurrent = false,
}) {
  final remainingWork = drainAfterCurrent
      ? (hasActiveCard ? 1 : 0)
      : remainingQueue + (hasActiveCard ? 1 : 0);
  final planned = plannedDispatchTotal(
    cardLimitMax: cardLimitMax,
    cardLimitCount: cardLimitCount,
    queueSize: processedCards + remainingWork,
  );
  final floor = dispatchProgressFloor(
    processedCards: processedCards,
    currentRound: currentRound,
    hasActiveCard: hasActiveCard,
  );
  return planned < floor ? floor : planned;
}

/// 停止后续卡片后，分母收成当前这张（或已处理张数）。
int clampedTotalAfterStop(AgentDispatchProgress progress) {
  if (!progress.running) return progress.processedCards;
  if (progress.currentRound > 0) return progress.currentRound;
  return progress.processedCards + 1;
}

/// 用看板实时队列校正分母；Max 模式会随待办增减，固定张数仍受上限约束。
AgentDispatchProgress applyLiveBoardQueue(
  AgentDispatchProgress progress, {
  required int remainingQueue,
  required bool hasActiveCard,
}) {
  if (!progress.running) return progress;
  final liveTotal = liveDispatchTotal(
    cardLimitMax: progress.cardLimitMax,
    cardLimitCount: progress.cardLimitCount,
    processedCards: progress.processedCards,
    remainingQueue: remainingQueue,
    hasActiveCard: hasActiveCard,
    currentRound: progress.currentRound,
    drainAfterCurrent: progress.drainAfterCurrent,
  );
  if (liveTotal == progress.totalCards) return progress;
  return progress.copyWith(totalCards: liveTotal);
}

final _roundPattern = RegExp(r'Worker 单卡轮次 (\d+)(?:/(\d+))?');
final _confirmedPattern = RegExp(r'Worker 确认第 (\d+) 次');
final _processedPattern = RegExp(r'已处理 (\d+) 张');
final _currentTitlePattern = RegExp(r'^当前卡片：(.+)$', multiLine: true);
final _currentDetailPattern = RegExp(r'^当前任务：([\s\S]+)$', multiLine: true);
final _afterQueuePattern = RegExp(r'完成后队列：开始「(.+)」');

/// 从 Worker 日志行更新进度；无法识别的行原样返回。
AgentDispatchProgress applyWorkerProgressLog(
  AgentDispatchProgress current,
  String message,
) {
  final round = _roundPattern.firstMatch(message);
  if (round != null) {
    final roundIndex = int.parse(round.group(1)!);
    final roundTotalRaw = round.group(2);
    final roundTotal = roundTotalRaw == null ? null : int.parse(roundTotalRaw);
    return current.copyWith(
      currentRound: roundIndex,
      totalCards: _totalAfterRoundLog(
        current,
        roundIndex: roundIndex,
        roundTotal: roundTotal,
      ),
      currentTitle: '',
      currentDetail: '',
      phaseLabel: '领取',
    );
  }
  final title = _currentTitlePattern.firstMatch(message);
  if (title != null) {
    return current.copyWith(
      currentTitle: title.group(1)!.trim(),
      phaseLabel: current.phaseLabel.isEmpty ? '领取' : current.phaseLabel,
    );
  }
  final detail = _currentDetailPattern.firstMatch(message);
  if (detail != null) {
    return current.copyWith(currentDetail: detail.group(1)!.trim());
  }
  final phase = _phaseFromLog(message);
  if (phase != null) {
    return current.copyWith(phaseLabel: phase);
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

String? _phaseFromLog(String message) {
  if (message.contains('Agent 会话暂时失败') && message.contains('自动重试')) {
    return '重试';
  }
  if (message.contains('Worker 正在实施')) return '实施';
  if (message.contains('验证已由 Agent 会话完成') ||
      message.contains('Worker 正在提交') ||
      message.contains('已验证、提交')) {
    return '提交';
  }
  if (message.contains('咨询卡') && message.contains('送交验证')) return '送验';
  if (message.contains('Worker 批次完成')) return '完成';
  final afterQueue = _afterQueuePattern.firstMatch(message);
  if (afterQueue != null) return afterQueue.group(1);
  if (message.contains('完成后队列：开始')) return '完成后队列';
  return null;
}

AgentDispatchProgress _withProcessed(
    AgentDispatchProgress current, int processed) {
  final total = current.totalCards > processed ? current.totalCards : processed;
  return current.copyWith(processedCards: processed, totalCards: total);
}

int _totalAfterRoundLog(
  AgentDispatchProgress current, {
  required int roundIndex,
  required int? roundTotal,
}) {
  final keep =
      roundIndex > current.totalCards ? roundIndex : current.totalCards;
  if (current.drainAfterCurrent) return keep;
  // Max 把 Worker 上限写成 999，那是哨兵不是队列长度。
  if (current.cardLimitMax || roundTotal == null) {
    return current.totalCards > 0 ? keep : current.totalCards;
  }
  return roundTotal > current.totalCards ? roundTotal : current.totalCards;
}
