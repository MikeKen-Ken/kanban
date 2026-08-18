import 'agent_dispatch_token_usage.dart';

/// 一次 Cursor 会话的 token 用量（Dashboard 口径，不含重复累计）。
class AgentDispatchTokenRecord {
  const AgentDispatchTokenRecord({
    required this.at,
    required this.inputTokens,
    required this.outputTokens,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.steps = 0,
    this.toolCalls = 0,
    this.repeatedToolCalls = 0,
    this.repeatedReads = 0,
    required this.totalTokens,
  });

  final DateTime at;

  /// 未缓存 prompt，对应 Dashboard Input。
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int steps;
  final int toolCalls;
  final int repeatedToolCalls;
  final int repeatedReads;
  final int totalTokens;

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'input': inputTokens,
        'output': outputTokens,
        'cacheRead': cacheReadTokens,
        'cacheWrite': cacheWriteTokens,
        if (steps > 0) 'steps': steps,
        if (toolCalls > 0) 'tools': toolCalls,
        if (repeatedToolCalls > 0) 'repeatedToolCalls': repeatedToolCalls,
        if (repeatedReads > 0) 'repeatedReads': repeatedReads,
        'total': totalTokens,
      };

  factory AgentDispatchTokenRecord.fromJson(Map<String, dynamic> json) {
    return AgentDispatchTokenRecord.fromUsage(
      at: DateTime.parse(json['at'] as String).toLocal(),
      inputTokens: (json['input'] as num?)?.toInt() ?? 0,
      outputTokens: (json['output'] as num?)?.toInt() ?? 0,
      cacheReadTokens: (json['cacheRead'] as num?)?.toInt() ?? 0,
      cacheWriteTokens: (json['cacheWrite'] as num?)?.toInt() ?? 0,
      steps: (json['steps'] as num?)?.toInt() ?? 0,
      toolCalls: (json['tools'] as num?)?.toInt() ?? 0,
      repeatedToolCalls: (json['repeatedToolCalls'] as num?)?.toInt() ?? 0,
      repeatedReads: (json['repeatedReads'] as num?)?.toInt() ?? 0,
      totalTokens: (json['total'] as num?)?.toInt() ?? 0,
    );
  }

  factory AgentDispatchTokenRecord.fromUsage({
    required DateTime at,
    required int inputTokens,
    required int outputTokens,
    int cacheReadTokens = 0,
    int cacheWriteTokens = 0,
    int steps = 0,
    int toolCalls = 0,
    int repeatedToolCalls = 0,
    int repeatedReads = 0,
    int totalTokens = 0,
  }) {
    final usage = toDashboardTokenUsage(
      CursorTokenUsageRaw(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cacheReadTokens: cacheReadTokens,
        cacheWriteTokens: cacheWriteTokens,
        totalTokens: totalTokens,
      ),
    );
    return AgentDispatchTokenRecord(
      at: at,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      cacheReadTokens: usage.cacheReadTokens,
      cacheWriteTokens: usage.cacheWriteTokens,
      steps: steps,
      toolCalls: toolCalls,
      repeatedToolCalls: repeatedToolCalls,
      repeatedReads: repeatedReads,
      totalTokens: usage.totalTokens,
    );
  }

  static final _pattern = RegExp(
    r'本会话 token：input=(\d+) output=(\d+)'
    r'(?: cacheRead=(\d+) cacheWrite=(\d+))? total=(\d+)'
    r'(?: steps=(\d+) tools=(\d+) repeatedToolCalls=(\d+) repeatedReads=(\d+))?',
  );

  /// 从 Worker 日志行解析用量；无法识别时返回 null。
  static AgentDispatchTokenRecord? tryParse(String message, {DateTime? at}) {
    final match = _pattern.firstMatch(message);
    if (match == null) return null;
    return AgentDispatchTokenRecord.fromUsage(
      at: at ?? DateTime.now(),
      inputTokens: int.parse(match.group(1)!),
      outputTokens: int.parse(match.group(2)!),
      cacheReadTokens: int.parse(match.group(3) ?? '0'),
      cacheWriteTokens: int.parse(match.group(4) ?? '0'),
      totalTokens: int.parse(match.group(5)!),
      steps: int.parse(match.group(6) ?? '0'),
      toolCalls: int.parse(match.group(7) ?? '0'),
      repeatedToolCalls: int.parse(match.group(8) ?? '0'),
      repeatedReads: int.parse(match.group(9) ?? '0'),
    );
  }
}

class AgentDispatchDailyToken {
  const AgentDispatchDailyToken({
    required this.day,
    required this.sessions,
    required this.inputTokens,
    required this.outputTokens,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    required this.totalTokens,
  });

  final DateTime day;
  final int sessions;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int totalTokens;

  int get averageTotal => sessions == 0 ? 0 : (totalTokens / sessions).round();
}

/// 工业界常见的会话用量汇总：总量、日均、每次平均、输入/输出拆分。
class AgentDispatchTokenStats {
  const AgentDispatchTokenStats({
    required this.records,
    required this.now,
  });

  final List<AgentDispatchTokenRecord> records;
  final DateTime now;

  int get sessionCount => records.length;

  int get totalInput => records.fold(0, (sum, item) => sum + item.inputTokens);

  int get totalCacheRead =>
      records.fold(0, (sum, item) => sum + item.cacheReadTokens);

  int get totalCacheWrite =>
      records.fold(0, (sum, item) => sum + item.cacheWriteTokens);

  int get totalOutput =>
      records.fold(0, (sum, item) => sum + item.outputTokens);

  int get totalTokens => records.fold(0, (sum, item) => sum + item.totalTokens);

  double? get averageInput =>
      sessionCount == 0 ? null : totalInput / sessionCount;

  double? get averageOutput =>
      sessionCount == 0 ? null : totalOutput / sessionCount;

  double? get averageTotal =>
      sessionCount == 0 ? null : totalTokens / sessionCount;

  AgentDispatchTokenRecord? get lastSession =>
      records.isEmpty ? null : records.last;

  AgentDispatchTokenRecord? get peakSession {
    if (records.isEmpty) return null;
    return records.reduce(
      (best, item) => item.totalTokens > best.totalTokens ? item : best,
    );
  }

  List<AgentDispatchTokenRecord> inRange(DateTime start, DateTime end) {
    return records
        .where((item) => !item.at.isBefore(start) && item.at.isBefore(end))
        .toList();
  }

  AgentDispatchTokenStats get today {
    final start = DateTime(now.year, now.month, now.day);
    return AgentDispatchTokenStats(
      records: inRange(start, start.add(const Duration(days: 1))),
      now: now,
    );
  }

  AgentDispatchTokenStats lastDays(int days) {
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    return AgentDispatchTokenStats(
      records: inRange(start, now.add(const Duration(days: 1))),
      now: now,
    );
  }

  /// 最近 [hours] 小时（相对 [now]，含当前时刻）。
  AgentDispatchTokenStats lastHours(int hours) {
    return AgentDispatchTokenStats(
      records: inRange(
        now.subtract(Duration(hours: hours)),
        now.add(const Duration(milliseconds: 1)),
      ),
      now: now,
    );
  }

  /// 最近 [days] 天，按本地日历日聚合（含无用量的空日）。
  List<AgentDispatchDailyToken> daily(int days) {
    final todayStart = DateTime(now.year, now.month, now.day);
    final buckets = <DateTime, List<AgentDispatchTokenRecord>>{};
    for (var i = days - 1; i >= 0; i--) {
      buckets[todayStart.subtract(Duration(days: i))] = [];
    }
    for (final record in records) {
      final day = DateTime(record.at.year, record.at.month, record.at.day);
      final bucket = buckets[day];
      if (bucket != null) bucket.add(record);
    }
    return [
      for (final entry in buckets.entries)
        AgentDispatchDailyToken(
          day: entry.key,
          sessions: entry.value.length,
          inputTokens: entry.value.fold(0, (s, r) => s + r.inputTokens),
          outputTokens: entry.value.fold(0, (s, r) => s + r.outputTokens),
          cacheReadTokens: entry.value.fold(0, (s, r) => s + r.cacheReadTokens),
          cacheWriteTokens:
              entry.value.fold(0, (s, r) => s + r.cacheWriteTokens),
          totalTokens: entry.value.fold(0, (s, r) => s + r.totalTokens),
        ),
    ];
  }
}
