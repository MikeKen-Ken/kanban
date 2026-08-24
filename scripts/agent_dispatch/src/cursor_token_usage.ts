/** Cursor SDK \u4E0A\u62A5\u7684\u4F1A\u8BDD\u7528\u91CF。`inputTokens` \u6709\u65F6\u5DF2\u542B\u7F13\u5B58\u547D\u4E2D。 */
export type CursorTokenUsage = {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  totalTokens?: number;
};

/** \u4E0E Cursor Dashboard \u5206\u9879\u4E00\u81F4、\u4E0D\u91CD\u590D\u7D2F\u8BA1\u7684\u7528\u91CF。 */
export type DashboardTokenUsage = {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  totalTokens: number;
};

export type SessionDiagnostics = {
  steps: number;
  toolCalls: number;
  repeatedToolCalls: number;
  repeatedReads: number;
};

function asCount(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.trunc(value));
}

/**
 * \u628A SDK `TokenUsage` \u6536\u6210 Dashboard \u53E3\u5F84：
 * Input \u4E3A\u672A\u7F13\u5B58 prompt；Total = Input + Cache Read + Cache Write + Output。
 * SDK \u82E5\u628A\u7F13\u5B58\u7B97\u8FDB input \u53C8\u52A0\u8FDB total，\u8FD9\u91CC\u4F1A\u62C6\u5F00，\u907F\u514D\u5408\u5E76\u65F6\u7FFB\u500D。
 */
export function toDashboardTokenUsage(
  raw: CursorTokenUsage,
): DashboardTokenUsage {
  const input = asCount(raw.inputTokens);
  const output = asCount(raw.outputTokens);
  const cacheRead = asCount(raw.cacheReadTokens);
  const cacheWrite = asCount(raw.cacheWriteTokens);
  const reportedTotal = asCount(raw.totalTokens);
  const cache = cacheRead + cacheWrite;
  const extra = reportedTotal - input - output;
  const inferredCache = cache > 0 ? cache : Math.max(0, extra);
  const inferredRead = cacheRead > 0 ? cacheRead : inferredCache;
  const inferredWrite = cacheWrite;
  const cacheSum = inferredRead + inferredWrite;
  const inputLooksInclusive =
    cacheSum > 0 && input >= cacheSum && extra >= cacheSum;

  if (inputLooksInclusive) {
    const uncached = input - cacheSum;
    return {
      inputTokens: uncached,
      outputTokens: output,
      cacheReadTokens: inferredRead,
      cacheWriteTokens: inferredWrite,
      totalTokens: uncached + output + cacheSum,
    };
  }

  return {
    inputTokens: input,
    outputTokens: output,
    cacheReadTokens: inferredRead,
    cacheWriteTokens: inferredWrite,
    totalTokens: input + output + cacheSum,
  };
}

export function formatSessionTokenLog(
  raw: CursorTokenUsage,
  diagnostics?: SessionDiagnostics,
): string {
  const usage = toDashboardTokenUsage(raw);
  return (
    `session tokens: input=${usage.inputTokens} output=${usage.outputTokens}` +
    ` cacheRead=${usage.cacheReadTokens} cacheWrite=${usage.cacheWriteTokens}` +
    ` total=${usage.totalTokens}` +
    (diagnostics
      ? ` steps=${diagnostics.steps} tools=${diagnostics.toolCalls}` +
        ` repeatedToolCalls=${diagnostics.repeatedToolCalls}` +
        ` repeatedReads=${diagnostics.repeatedReads}`
      : "")
  );
}
