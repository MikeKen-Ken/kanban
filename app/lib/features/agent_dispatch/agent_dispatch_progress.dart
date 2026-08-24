import 'dart:convert';

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
    this.engine = '',
    this.model = '',
    this.modelParams = const {},
    this.batchStartedAt,
    this.cardStartedAt,
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

  /// 批次默认或本卡覆盖后的引擎名（cursor / codex）。
  final String engine;

  /// 批次默认或本卡覆盖后的模型 id。
  final String model;

  /// 当前生效的模型参数，如 context / fast / reasoning_effort。
  final Map<String, String> modelParams;

  /// 本批次开始时刻，供总览展示总体已运行时间。
  final DateTime? batchStartedAt;

  /// 当前卡片领取时刻，供总览展示本卡运行时间。
  final DateTime? cardStartedAt;

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

  int? batchElapsedSeconds({DateTime? now}) =>
      elapsedSecondsSince(batchStartedAt, now: now);

  int? cardElapsedSeconds({DateTime? now}) =>
      elapsedSecondsSince(cardStartedAt, now: now);

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
    String? engine,
    String? model,
    Map<String, String>? modelParams,
    DateTime? batchStartedAt,
    DateTime? cardStartedAt,
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
      engine: engine ?? this.engine,
      model: model ?? this.model,
      modelParams: modelParams ?? this.modelParams,
      batchStartedAt: batchStartedAt ?? this.batchStartedAt,
      cardStartedAt: cardStartedAt ?? this.cardStartedAt,
    );
  }
}

int? elapsedSecondsSince(DateTime? start, {DateTime? now}) {
  if (start == null) return null;
  final seconds = (now ?? DateTime.now()).difference(start).inSeconds;
  return seconds < 0 ? 0 : seconds;
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

final _roundPattern = RegExp(r'Worker (?:card round|单卡轮次) (\d+)(?:/(\d+))?');
final _confirmedPattern = RegExp(r'Worker 确认第 (\d+) 次');
final _processedPattern = RegExp(r'(?:已处理 (\d+) 张|processed (\d+) card\(s\))');
final _currentTitlePattern =
    RegExp(r'^(?:当前卡片：|Current card: )(.+)$', multiLine: true);
final _currentDetailPattern =
    RegExp(r'^(?:当前任务：|Current task: )([\s\S]+)$', multiLine: true);
final _afterQueuePattern = RegExp(
  r'(?:完成后队列：开始[「『](.+)[」』]|Completion queue: starting [“"](.+)[”"])',
);
final _cardOverridePattern = RegExp(
  r'(?:本卡覆盖：|Card override: )engine=(\w+) model=([^\s]+)(?: params=(\[.*?\]))?',
);
final _cursorModelPattern = RegExp(r'Cursor (?:模型|model)=([^\s]+)');

/// 从 Worker 日志行更新进度；无法识别的行原样返回。
AgentDispatchProgress applyWorkerProgressLog(
  AgentDispatchProgress current,
  String message, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
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
      phaseLabel: 'Claim',
      cardStartedAt: clock,
    );
  }
  final title = _currentTitlePattern.firstMatch(message);
  if (title != null) {
    return current.copyWith(
      currentTitle: title.group(1)!.trim(),
      phaseLabel: current.phaseLabel.isEmpty ? 'Claim' : current.phaseLabel,
      cardStartedAt: current.cardStartedAt ?? clock,
    );
  }
  final override = _cardOverridePattern.firstMatch(message);
  if (override != null) {
    final rawParams = override.group(3);
    return current.copyWith(
      engine: override.group(1)!.trim(),
      model: override.group(2)!.trim(),
      modelParams: rawParams == null
          ? null
          : parseAgentDispatchLoggedModelParams(rawParams),
    );
  }
  final cursorModel = _cursorModelPattern.firstMatch(message);
  if (cursorModel != null) {
    return current.copyWith(model: cursorModel.group(1)!.trim());
  }
  final detail = _currentDetailPattern.firstMatch(message);
  if (detail != null) {
    return current.copyWith(currentDetail: detail.group(1)!.trim());
  }
  final phase = _phaseFromLog(message);
  final absoluteProcessed = _absoluteProcessedFromLog(message);
  final completedCard =
      absoluteProcessed == null && _isCompletedCardLog(message);
  if (phase == null && absoluteProcessed == null && !completedCard) {
    return current;
  }
  var next = phase != null ? current.copyWith(phaseLabel: phase) : current;
  if (absoluteProcessed != null) {
    next = _withProcessed(next, absoluteProcessed);
  } else if (completedCard) {
    next = _withProcessed(next, current.processedCards + 1);
  }
  return next;
}

int? _absoluteProcessedFromLog(String message) {
  final confirmed = _confirmedPattern.firstMatch(message);
  if (confirmed != null) return int.parse(confirmed.group(1)!);
  final processed = _processedPattern.firstMatch(message);
  if (processed != null) return _firstCapturedInt(processed);
  return null;
}

bool _isCompletedCardLog(String message) {
  return RegExp(r'卡片 \S+ 已验证、提交并送交人工验证').hasMatch(message) ||
      RegExp(r'咨询卡 \S+ 已送交验证').hasMatch(message) ||
      message.contains('已恢复 pending 会话') ||
      RegExp(r'Card \S+ was validated, committed, and submitted for manual verification')
          .hasMatch(message) ||
      RegExp(r'Consultation card \S+ was submitted for verification')
          .hasMatch(message) ||
      message.contains('Recovered pending session');
}

String? _phaseFromLog(String message) {
  if ((message.contains('Agent 会话暂时失败') && message.contains('自动重试')) ||
      (message.contains('Agent session temporarily failed') &&
          message.contains('retrying'))) {
    return 'Retry';
  }
  if (message.contains('Worker 正在实施') ||
      message.contains('Worker is processing the current card')) {
    return 'Implement';
  }
  if (message.contains('验证已由 Agent 会话完成') ||
      message.contains('Worker 正在提交') ||
      message.contains('已验证、提交') ||
      message.contains('Validation was completed in the Agent session') ||
      message.contains('Worker is finalizing the current card') ||
      message.contains('was validated, committed')) {
    return 'Submit';
  }
  if ((message.contains('咨询卡') && message.contains('送交验证')) ||
      (message.contains('Consultation card') &&
          message.contains('submitted for verification'))) {
    return 'Verify';
  }
  if (message.contains('Worker 批次完成') ||
      message.contains('Worker batch completed')) {
    return 'Complete';
  }
  final afterQueue = _afterQueuePattern.firstMatch(message);
  if (afterQueue != null) {
    final label = _firstCapturedString(afterQueue);
    return switch (label) {
      '上传' || 'Upload' => 'Upload',
      '推送' || 'Push' => 'Push',
      '休眠' || 'Hibernate' => 'Hibernate',
      '关机' || 'Shutdown' => 'Shutdown',
      _ => label,
    };
  }
  if (message.contains('完成后队列：开始') ||
      message.contains('Completion queue: starting')) {
    return 'Completion queue';
  }
  return null;
}

int? _firstCapturedInt(RegExpMatch match) {
  final text = _firstCapturedString(match);
  return text == null ? null : int.parse(text);
}

String? _firstCapturedString(RegExpMatch match) {
  for (var i = 1; i <= match.groupCount; i++) {
    final value = match.group(i);
    if (value != null) return value;
  }
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

Map<String, String> agentDispatchModelParamMap(
  Iterable<({String id, String value})> items,
) {
  final result = <String, String>{};
  for (final item in items) {
    final id = item.id.trim();
    final value = item.value.trim();
    if (id.isEmpty || value.isEmpty) continue;
    result[id] = value;
  }
  return result;
}

Map<String, String> parseAgentDispatchLoggedModelParams(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const {};
    final result = <String, String>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final id = '${item['id'] ?? ''}'.trim();
      final value = '${item['value'] ?? ''}'.trim();
      if (id.isEmpty || value.isEmpty) continue;
      result[id] = value;
    }
    return result;
  } catch (_) {
    return const {};
  }
}
