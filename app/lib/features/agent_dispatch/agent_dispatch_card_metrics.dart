import 'agent_dispatch_log.dart';
import 'agent_dispatch_progress.dart';
import 'agent_dispatch_token.dart';

/// 从当前卡片日志切片解析出的运行指标，供日志上方状态区展示。
class AgentDispatchCardMetrics {
  const AgentDispatchCardMetrics({
    this.token,
    this.elapsedSeconds,
    this.steps,
    this.toolCalls,
    this.engine,
    this.model,
    this.retryCount = 0,
    this.cursorRunId,
  });

  final AgentDispatchTokenRecord? token;
  final int? elapsedSeconds;
  final int? steps;
  final int? toolCalls;
  final String? engine;
  final String? model;
  final int retryCount;
  final String? cursorRunId;

  bool get hasAny =>
      token != null ||
      elapsedSeconds != null ||
      steps != null ||
      toolCalls != null ||
      (engine != null && engine!.isNotEmpty) ||
      (model != null && model!.isNotEmpty) ||
      retryCount > 0 ||
      (cursorRunId != null && cursorRunId!.isNotEmpty);

  /// 解析单张卡片的日志切片。
  static AgentDispatchCardMetrics parse(
    String logSlice, {
    bool running = false,
    DateTime? now,
  }) {
    if (logSlice.trim().isEmpty) return const AgentDispatchCardMetrics();

    final lines = logSlice.split('\n').where((line) => line.trim().isNotEmpty);
    AgentDispatchTokenRecord? token;
    int? elapsedMs;
    int? steps;
    int? toolCalls;
    String? engine;
    String? model;
    String? cursorRunId;
    var retryCount = 0;

    for (final line in lines) {
      final message = AgentDispatchLogEntry.messageOf(line);
      token = AgentDispatchTokenRecord.tryParse(message) ?? token;

      final override = _cardOverridePattern.firstMatch(message);
      if (override != null) {
        engine = override.group(1);
        model = override.group(2);
      }

      final cursorModel = _cursorModelPattern.firstMatch(message);
      if (cursorModel != null) {
        model ??= cursorModel.group(1);
      }

      final run = _cursorRunPattern.firstMatch(message);
      if (run != null) {
        cursorRunId = run.group(1);
        steps = int.tryParse(run.group(2) ?? '');
        toolCalls = int.tryParse(run.group(3) ?? '');
        elapsedMs = int.tryParse(run.group(4) ?? '');
      }

      final codex = _codexElapsedPattern.firstMatch(message);
      if (codex != null) {
        elapsedMs = int.tryParse(codex.group(1) ?? '');
      }

      final retry = _retryPattern.firstMatch(message);
      if (retry != null) {
        final attempt = int.tryParse(retry.group(1) ?? '') ?? 0;
        if (attempt > retryCount) retryCount = attempt;
      }
    }

    final elapsedSeconds = elapsedMs != null
        ? (elapsedMs / 1000).ceil()
        : _elapsedFromTimestamps(
            logSlice,
            running: running,
            now: now ?? DateTime.now(),
          );

    return AgentDispatchCardMetrics(
      token: token,
      elapsedSeconds: elapsedSeconds,
      steps: steps,
      toolCalls: toolCalls,
      engine: engine,
      model: model,
      retryCount: retryCount,
      cursorRunId: cursorRunId,
    );
  }

  /// 从完整日志中定位当前卡片切片并解析指标。
  static AgentDispatchCardMetrics? forCurrentTask(
    String fullLog,
    AgentDispatchProgress progress, {
    bool running = false,
    DateTime? now,
  }) {
    final text = fullLog.trim();
    if (text.isEmpty) return null;

    final tasks = AgentDispatchLogTasks.parse(text.split('\n'));
    if (tasks.isEmpty) return null;

    final ordinal = _currentTaskOrdinal(progress, tasks);
    final slice = AgentDispatchLogTasks.slice(text, ordinal);
    if (slice.trim().isEmpty) return null;

    final metrics = parse(slice, running: running, now: now);
    if (!metrics.hasAny && !progress.running) return null;
    return metrics;
  }

  static int? _currentTaskOrdinal(
    AgentDispatchProgress progress,
    List<AgentDispatchLogTask> tasks,
  ) {
    if (progress.running && progress.currentRound > 0) {
      final match =
          tasks.where((task) => task.ordinal == progress.currentRound);
      if (match.isNotEmpty) return progress.currentRound;
    }
    return tasks.last.ordinal;
  }

  static int? _elapsedFromTimestamps(
    String logSlice, {
    required bool running,
    required DateTime now,
  }) {
    final stamps = <DateTime>[];
    for (final line in logSlice.split('\n')) {
      final match = _timestampPattern.firstMatch(line);
      if (match == null) continue;
      final parts = match.group(1)!.split(':');
      if (parts.length != 3) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      final second = int.tryParse(parts[2]);
      if (hour == null || minute == null || second == null) continue;
      stamps.add(DateTime(now.year, now.month, now.day, hour, minute, second));
    }
    if (stamps.isEmpty) return null;

    final start = stamps.first;
    var end = running ? now : stamps.last;
    if (end.isBefore(start)) {
      end = end.add(const Duration(days: 1));
    }
    final seconds = end.difference(start).inSeconds;
    return seconds < 0 ? null : seconds;
  }

  static final _timestampPattern = RegExp(r'^\[(\d{2}:\d{2}:\d{2})\]');
  static final _cardOverridePattern =
      RegExp(r'本卡覆盖：engine=(\w+) model=([^\s]+)');
  static final _cursorModelPattern = RegExp(r'Cursor 模型=([^\s]+)');
  static final _cursorRunPattern = RegExp(
    r'Cursor run id=(\S+) status=\S+ steps=(\d+) tools=(\d+) elapsedMs=(\d+)',
  );
  static final _codexElapsedPattern =
      RegExp(r'Codex exec (?:exitCode=\d+|skipped|cancelled) elapsedMs=(\d+)');
  static final _retryPattern =
      RegExp(r'Agent 会话暂时失败（第 (\d+)/\d+ 次）');
}

String formatAgentDispatchElapsed(int seconds) {
  if (seconds < 60) return '${seconds}秒';
  final minutes = seconds ~/ 60;
  final remain = seconds % 60;
  if (minutes < 60) {
    return remain == 0 ? '${minutes}分' : '${minutes}分${remain}秒';
  }
  final hours = minutes ~/ 60;
  final remainMinutes = minutes % 60;
  if (remainMinutes == 0) return '${hours}小时';
  return '${hours}小时${remainMinutes}分';
}

String formatAgentDispatchTokenCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) {
    final scaled = value / 1000;
    return scaled >= 100
        ? '${scaled.round()}K'
        : '${scaled.toStringAsFixed(1)}K';
  }
  final scaled = value / 1000000;
  return scaled >= 100
      ? '${scaled.round()}M'
      : '${scaled.toStringAsFixed(1)}M';
}
