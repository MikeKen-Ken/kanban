/** 与 Dart `dispatch_shell_spans.dart` 同一套判定，避免 SDK 提前 completed 时误放行。 */

export type ShellSpan = {
  callId: string;
  command: string;
  startedAtMs: number;
  endedAtMs?: number;
  executionTimeMs?: number;
  exitCode?: number;
};

/** 与 Dart `dispatch_shell_spans.dart` 保持一致。 */
const VERIFICATION_MARKERS = [
  "flutter test",
  "flutter analyze",
  "dart test",
  "dart analyze",
  "dotnet test",
  "node --test",
  "node.exe --test",
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

/** 实际结束时间优先 startedAt+executionTime，避免观察滞后把短失败排到成功测试之后。 */
export function shellEffectiveEndMs(span: ShellSpan): number {
  const exec = span.executionTimeMs ?? 0;
  if (exec > 0) return span.startedAtMs + exec;
  if (span.endedAtMs == null) return Number.MAX_SAFE_INTEGER;
  return span.endedAtMs;
}

export function commandLooksLikeCdAndChain(command: string): boolean {
  return /\bcd\b[^&\n]*&&/i.test(command);
}

export function isUneexecutedCdAndVerification(span: ShellSpan): boolean {
  const code = span.exitCode;
  if (code == null || code === 0) return false;
  if (!commandLooksLikeCdAndChain(span.command)) return false;
  if (!isVerificationCommand(span.command)) return false;
  const exec = span.executionTimeMs;
  if (exec != null && exec >= 3_000) return false;
  return true;
}

export function readyBlockedByShells(
  spans: readonly ShellSpan[],
  nowMs: number,
): string | undefined {
  const verification = spans.filter((span) => isVerificationCommand(span.command));
  if (verification.length === 0) return undefined;
  const authoritative = verification.filter(
    (span) => !isUneexecutedCdAndVerification(span),
  );
  const pool = authoritative.length > 0 ? authoritative : verification;
  let lastVerification: ShellSpan | undefined;
  let lastEndMs = -1;
  for (const span of pool) {
    const endMs = shellEffectiveEndMs(span);
    if (lastVerification == null || endMs >= lastEndMs) {
      lastVerification = span;
      lastEndMs = endMs;
    }
  }
  if (!lastVerification) return undefined;
  if (nowMs < lastEndMs) {
    return (
      `验证命令仍在执行：${clip(lastVerification.command)}。` +
      "请等待测试完成后再调用 ready_to_submit，不要与 Shell 并行。"
    );
  }
  const code = lastVerification.exitCode;
  if (code != null && code !== 0) {
    const hint = commandLooksLikeCdAndChain(lastVerification.command)
      ? "PowerShell 5.1 不支持 &&；请用 working_directory，不要写 cd ... &&。"
      : "请修复后重跑测试，再调用 ready_to_submit。";
    return `验证命令失败（exitCode=${code}）：${clip(lastVerification.command)}。${hint}`;
  }
  return undefined;
}

function clip(command: string): string {
  const text = command.trim();
  return text.length <= 180 ? text : `${text.slice(0, 179)}…`;
}
