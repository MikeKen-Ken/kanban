/// 一次 Cursor 会话的 token 用量。
class AgentDispatchTokenRecord {
  const AgentDispatchTokenRecord({
    required this.at,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });

  final DateTime at;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'input': inputTokens,
        'output': outputTokens,
        'total': totalTokens,
      };

  factory AgentDispatchTokenRecord.fromJson(Map<String, dynamic> json) {
    return AgentDispatchTokenRecord(
      at: DateTime.parse(json['at'] as String).toLocal(),
      inputTokens: (json['input'] as num).toInt(),
      outputTokens: (json['output'] as num).toInt(),
      totalTokens: (json['total'] as num).toInt(),
    );
  }

  static final _pattern = RegExp(
    r'本会话 token：input=(\d+) output=(\d+) total=(\d+)',
  );

  /// 从 Worker 日志行解析用量；无法识别时返回 null。
  static AgentDispatchTokenRecord? tryParse(String message, {DateTime? at}) {
    final match = _pattern.firstMatch(message);
    if (match == null) return null;
    return AgentDispatchTokenRecord(
      at: at ?? DateTime.now(),
      inputTokens: int.parse(match.group(1)!),
      outputTokens: int.parse(match.group(2)!),
      totalTokens: int.parse(match.group(3)!),
    );
  }
}

class AgentDispatchDailyToken {
  const AgentDispatchDailyToken({
    required this.day,
    required this.sessions,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });

  final DateTime day;
  final int sessions;
  final int inputTokens;
  final int outputTokens;
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

  int get totalInput =>
      records.fold(0, (sum, item) => sum + item.inputTokens);

  int get totalOutput =>
      records.fold(0, (sum, item) => sum + item.outputTokens);

  int get totalTokens =>
      records.fold(0, (sum, item) => sum + item.totalTokens);

  double? get averageInput =>
      sessionCount == 0 ? null : totalInput / sessionCount;

  double? get averageOutput =>
      sessionCount == 0 ? null : totalOutput / sessionCount;

  double? get averageTotal =>
      sessionCount == 0 ? null : totalTokens / sessionCount;

  double? get inputShare =>
      totalTokens == 0 ? null : totalInput / totalTokens;

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
          totalTokens: entry.value.fold(0, (s, r) => s + r.totalTokens),
        ),
    ];
  }
}
