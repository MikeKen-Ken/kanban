/** 与 Dart `dispatch_shell_spans.dart` 同一套判定，避免 SDK 提前 completed 时误放行。 */

export type ShellSpan = {
  callId: string;
  command: string;
  startedAtMs: number;
  endedAtMs?: number;
  executionTimeMs?: number;
  exitCode?: number;
};

const VERIFICATION_MARKERS = [
  "flutter test",
  "dart test",
  "dotnet test",
  "npm test",
  "npx test",
  "pnpm test",
  "yarn test",
  "pytest",
  "cargo test",
  "go test",
  "mvn test",
  "gradle test",
  "gradlew test",
  "ctest",
  "vitest",
  "jest",
];

export function isVerificationCommand(command: string): boolean {
  const text = command.toLowerCase();
  return VERIFICATION_MARKERS.some((marker) => text.includes(marker));
}

export function shellEffectiveEndMs(span: ShellSpan): number {
  const ended = span.endedAtMs;
  if (ended == null) return Number.MAX_SAFE_INTEGER;
  const exec = span.executionTimeMs ?? 0;
  const started = span.startedAtMs;
  return ended > started + exec ? ended : started + exec;
}

export function readyBlockedByShells(
  spans: readonly ShellSpan[],
  nowMs: number,
): string | undefined {
  let lastVerification: ShellSpan | undefined;
  for (const span of spans) {
    if (!isVerificationCommand(span.command)) continue;
    lastVerification = span;
    if (nowMs < shellEffectiveEndMs(span)) {
      return (
        `验证命令仍在执行：${clip(span.command)}。` +
        "请等待测试完成后再调用 ready_to_submit，不要与 Shell 并行。"
      );
    }
  }
  const failed = lastVerification;
  if (failed && failed.exitCode != null && failed.exitCode !== 0) {
    return (
      `验证命令失败（exitCode=${failed.exitCode}）：${clip(failed.command)}。` +
      "请修复后重跑测试，再调用 ready_to_submit。"
    );
  }
  return undefined;
}

function clip(command: string): string {
  const text = command.trim();
  return text.length <= 180 ? text : `${text.slice(0, 179)}…`;
}
