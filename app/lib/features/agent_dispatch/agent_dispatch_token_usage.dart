/// Cursor SDK 原始用量；`inputTokens` 有时已含缓存命中。
class CursorTokenUsageRaw {
  const CursorTokenUsageRaw({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalTokens = 0,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int totalTokens;
}

/// 与 Cursor Dashboard 分项一致、不重复累计的用量。
class DashboardTokenUsage {
  const DashboardTokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.totalTokens,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int totalTokens;
}

int _asCount(int value) => value < 0 ? 0 : value;

/// 把 SDK 用量收成 Dashboard 口径，避免 cache 同时计入 input 与 total。
DashboardTokenUsage toDashboardTokenUsage(CursorTokenUsageRaw raw) {
  final input = _asCount(raw.inputTokens);
  final output = _asCount(raw.outputTokens);
  final cacheRead = _asCount(raw.cacheReadTokens);
  final cacheWrite = _asCount(raw.cacheWriteTokens);
  final reportedTotal = _asCount(raw.totalTokens);
  final cache = cacheRead + cacheWrite;
  final extra = reportedTotal - input - output;
  final inferredCache = cache > 0 ? cache : (extra > 0 ? extra : 0);
  final inferredRead = cacheRead > 0 ? cacheRead : inferredCache;
  final inferredWrite = cacheWrite;
  final cacheSum = inferredRead + inferredWrite;
  final inputLooksInclusive =
      cacheSum > 0 && input >= cacheSum && extra >= cacheSum;

  if (inputLooksInclusive) {
    final uncached = input - cacheSum;
    return DashboardTokenUsage(
      inputTokens: uncached,
      outputTokens: output,
      cacheReadTokens: inferredRead,
      cacheWriteTokens: inferredWrite,
      totalTokens: uncached + output + cacheSum,
    );
  }

  return DashboardTokenUsage(
    inputTokens: input,
    outputTokens: output,
    cacheReadTokens: inferredRead,
    cacheWriteTokens: inferredWrite,
    totalTokens: input + output + cacheSum,
  );
}
