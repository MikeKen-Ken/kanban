/** \u4E0E Dart `dispatch_shell_spans.dart` \u540C\u4E00\u5957\u5224\u5B9A，\u907F\u514D SDK \u63D0\u524D completed \u65F6\u8BEF\u653E\u884C。 */

export type ShellSpan = {
  callId: string;
  command: string;
  startedAtMs: number;
  endedAtMs?: number;
  executionTimeMs?: number;
  exitCode?: number;
};

/** \u4E0E Dart `dispatch_shell_spans.dart` \u4FDD\u6301\u4E00\u81F4。 */
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

/** \u4E0E Dart `kDispatchImplausibleTestDurationMs` \u4FDD\u6301\u4E00\u81F4。 */
export const IMPLAUSIBLE_TEST_DURATION_MS = 2_000;

export function isSlowTestCommand(command: string): boolean {
  const text = command.toLowerCase();
  return text.includes("flutter test") || text.includes("dart test");
}

/** \u89C2\u5BDF\u8017\u65F6：\u4F18\u5148 SDK executionTime，\u5426\u5219 endedAt-startedAt；\u672A\u77E5\u4E3A -1。 */
export function shellObservedDurationMs(span: ShellSpan): number {
  const exec = span.executionTimeMs ?? 0;
  if (exec > 0) return exec;
  if (span.endedAtMs == null) return -1;
  return span.endedAtMs - span.startedAtMs;
}

/** \u5B9E\u9645\u7ED3\u675F\u65F6\u95F4\u4F18\u5148 startedAt+executionTime，\u907F\u514D\u89C2\u5BDF\u6EDE\u540E\u628A\u77ED\u5931\u8D25\u6392\u5230\u6210\u529F\u6D4B\u8BD5\u4E4B\u540E。 */
export function shellEffectiveEndMs(span: ShellSpan): number {
  const exec = span.executionTimeMs ?? 0;
  if (exec > 0) return span.startedAtMs + exec;
  if (span.endedAtMs == null) return Number.MAX_SAFE_INTEGER;
  return span.endedAtMs;
}

export function isImplausiblyShortSuccessfulTest(span: ShellSpan): boolean {
  if (!isSlowTestCommand(span.command)) return false;
  if (span.exitCode != null && span.exitCode !== 0) return false;
  const duration = shellObservedDurationMs(span);
  if (duration < 0) return false;
  return duration < IMPLAUSIBLE_TEST_DURATION_MS;
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
      `Verification command is still running: ${clip(lastVerification.command)}. ` +
      "Wait for the test to finish before calling ready_to_submit; do not run it in parallel with Shell."
    );
  }
  const code = lastVerification.exitCode;
  if (code != null && code !== 0) {
    const hint = commandLooksLikeCdAndChain(lastVerification.command)
      ? "PowerShell 5.1 does not support &&; use working_directory instead of cd ... &&."
      : "Fix the issue and rerun the test before calling ready_to_submit.";
    return `Verification command failed (exitCode=${code}): ${clip(lastVerification.command)}. ${hint}`;
  }
  if (isImplausiblyShortSuccessfulTest(lastVerification)) {
    const duration = shellObservedDurationMs(lastVerification);
    return (
      `Verification command finished implausibly quickly (${duration}ms): ` +
      `${clip(lastVerification.command)}. ` +
      "Confirm that working_directory and relative paths match, then wait for flutter test / dart test to actually finish before ready_to_submit."
    );
  }
  return undefined;
}

function clip(command: string): string {
  const text = command.trim();
  return text.length <= 180 ? text : `${text.slice(0, 179)}…`;
}
