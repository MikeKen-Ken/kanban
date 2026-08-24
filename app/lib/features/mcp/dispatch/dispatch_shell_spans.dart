/// Worker 上报的会话内 Shell 时间线。用于拒绝测试尚未结束时的 ready_to_submit。
class DispatchShellSpan {
  const DispatchShellSpan({
    required this.callId,
    required this.command,
    required this.startedAtMs,
    this.endedAtMs,
    this.executionTimeMs,
    this.exitCode,
  });

  final String callId;
  final String command;
  final int startedAtMs;
  final int? endedAtMs;
  final int? executionTimeMs;
  final int? exitCode;

  DispatchShellSpan copyWith({
    int? endedAtMs,
    int? executionTimeMs,
    int? exitCode,
  }) {
    return DispatchShellSpan(
      callId: callId,
      command: command,
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs ?? this.endedAtMs,
      executionTimeMs: executionTimeMs ?? this.executionTimeMs,
      exitCode: exitCode ?? this.exitCode,
    );
  }
}

/// 识别会作为本卡验收依据的测试 / 静态检查命令。
///
/// 与 `scripts/agent_dispatch/src/verification_ready_gate.ts` 保持一致。
bool isDispatchVerificationCommand(String command) {
  final text = command.toLowerCase();
  const markers = [
    'flutter test',
    'flutter analyze',
    'dart test',
    'dart analyze',
    'dotnet test',
    'node --test',
    'node.exe --test',
    'npm test',
    'npx test',
    'pnpm test',
    'yarn test',
    'pytest',
    'cargo test',
    'go test',
    'mvn test',
    'gradle test',
    'gradlew test',
    'ctest',
    'vitest',
    'jest',
  ];
  return markers.any(text.contains);
}

/// SDK 的 call_id 经常是 `call_…\nfc_…` 两行；MCP JSON 与字符串闸门都需要单行 id。
String normalizeDispatchCallId(String? callId) {
  final parts = (callId ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty);
  return parts.join('_');
}

/// `flutter test` / `dart test` 冷启动通常远长于此；更短的成功退出多半没真正跑测试。
const int kDispatchImplausibleTestDurationMs = 2000;

bool isDispatchSlowTestCommand(String command) {
  final text = command.toLowerCase();
  return text.contains('flutter test') || text.contains('dart test');
}

/// 观察耗时：优先 SDK `executionTime`，否则 `endedAt - startedAt`；未知为 -1。
int dispatchShellObservedDurationMs(DispatchShellSpan span) {
  final exec = span.executionTimeMs ?? 0;
  if (exec > 0) return exec;
  final ended = span.endedAtMs;
  if (ended == null) return -1;
  return ended - span.startedAtMs;
}

/// 实际结束时间优先 `startedAt + executionTime`。
/// SDK 可能提前 completed（endedAt 过早），Worker 观察也可能滞后（endedAt 过晚）；
/// 二者都不能用来覆盖 SDK 给出的 executionTime。
int dispatchShellEffectiveEndMs(DispatchShellSpan span) {
  final exec = span.executionTimeMs ?? 0;
  if (exec > 0) return span.startedAtMs + exec;
  final ended = span.endedAtMs;
  if (ended == null) return 0x7fffffffffffffff;
  return ended;
}

bool isImplausiblyShortSuccessfulTest(DispatchShellSpan span) {
  if (!isDispatchSlowTestCommand(span.command)) return false;
  final code = span.exitCode;
  if (code != null && code != 0) return false;
  final duration = dispatchShellObservedDurationMs(span);
  if (duration < 0) return false;
  return duration < kDispatchImplausibleTestDurationMs;
}

/// Windows PowerShell 5.1 无法解析 `cd dir && cmd`，这类失败从未真正跑测试。
bool commandLooksLikeCdAndChain(String command) {
  return RegExp(r'\bcd\b[^&\n]*&&', caseSensitive: false).hasMatch(command);
}

bool isUneexecutedCdAndVerification(DispatchShellSpan span) {
  final code = span.exitCode;
  if (code == null || code == 0) return false;
  if (!commandLooksLikeCdAndChain(span.command)) return false;
  if (!isDispatchVerificationCommand(span.command)) return false;
  final exec = span.executionTimeMs;
  if (exec != null && exec >= 3000) return false;
  return true;
}

String? dispatchReadyBlockedByShells(
  Iterable<DispatchShellSpan> spans, {
  required int nowMs,
}) {
  final verification = [
    for (final span in spans)
      if (isDispatchVerificationCommand(span.command)) span,
  ];
  if (verification.isEmpty) return null;
  final authoritative = [
    for (final span in verification)
      if (!isUneexecutedCdAndVerification(span)) span,
  ];
  final pool = authoritative.isNotEmpty ? authoritative : verification;
  DispatchShellSpan? lastVerification;
  var lastEndMs = -1;
  for (final span in pool) {
    final endMs = dispatchShellEffectiveEndMs(span);
    if (lastVerification == null || endMs >= lastEndMs) {
      lastVerification = span;
      lastEndMs = endMs;
    }
  }
  if (lastVerification == null) return null;
  if (nowMs < lastEndMs) {
    return 'The verification command is still running: ${_clip(lastVerification.command)}. '
        'Wait for the test to finish before calling ready_to_submit; do not run it in parallel with the Shell command.';
  }
  final code = lastVerification.exitCode;
  if (code != null && code != 0) {
    final hint = commandLooksLikeCdAndChain(lastVerification.command)
        ? 'PowerShell 5.1 does not support &&. Use working_directory instead of cd ... &&.'
        : 'Fix the issue, rerun the test, and then call ready_to_submit.';
    return 'The verification command failed (exitCode=$code): ${_clip(lastVerification.command)}. $hint';
  }
  if (isImplausiblyShortSuccessfulTest(lastVerification)) {
    final duration = dispatchShellObservedDurationMs(lastVerification);
    return 'The verification command finished implausibly quickly (${duration}ms): '
        '${_clip(lastVerification.command)}. Confirm that working_directory matches '
        'the relative paths, and wait for flutter test / dart test to finish before '
        'calling ready_to_submit.';
  }
  return null;
}

class DispatchShellSpanStore {
  DispatchShellSpanStore({int Function()? nowMs})
      : _nowMs = nowMs ?? _systemNowMs;

  static DispatchShellSpanStore instance = DispatchShellSpanStore();

  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  static void debugReset() {
    instance = DispatchShellSpanStore();
  }

  final int Function() _nowMs;
  final _spans = <String, Map<String, DispatchShellSpan>>{};

  int get nowMs => _nowMs();

  void clearSession(String sessionId) {
    _spans.remove(sessionId.trim());
  }

  void report({
    required String sessionId,
    required String callId,
    required String command,
    required String phase,
    int? startedAtMs,
    int? endedAtMs,
    int? executionTimeMs,
    int? exitCode,
  }) {
    final sid = sessionId.trim();
    final id = callId.trim();
    if (sid.isEmpty || id.isEmpty) return;
    final byCall = _spans.putIfAbsent(sid, () => <String, DispatchShellSpan>{});
    final now = _nowMs();
    final existing = byCall[id];
    if (phase == 'end') {
      byCall[id] = DispatchShellSpan(
        callId: id,
        command: command.trim().isEmpty
            ? (existing?.command ?? command)
            : command.trim(),
        startedAtMs: startedAtMs ?? existing?.startedAtMs ?? now,
        endedAtMs: endedAtMs ?? now,
        executionTimeMs: executionTimeMs ?? existing?.executionTimeMs,
        exitCode: exitCode ?? existing?.exitCode,
      );
      return;
    }
    byCall[id] = DispatchShellSpan(
      callId: id,
      command: command.trim(),
      startedAtMs: startedAtMs ?? existing?.startedAtMs ?? now,
      endedAtMs: existing?.endedAtMs,
      executionTimeMs: existing?.executionTimeMs,
      exitCode: existing?.exitCode,
    );
  }

  String? readyBlockedReason(String sessionId, {int? nowMs}) {
    final byCall = _spans[sessionId.trim()];
    if (byCall == null || byCall.isEmpty) return null;
    return dispatchReadyBlockedByShells(
      byCall.values,
      nowMs: nowMs ?? _nowMs(),
    );
  }
}

String _clip(String command) {
  final text = command.trim();
  if (text.length <= 180) return text;
  return '${text.substring(0, 179)}…';
}
