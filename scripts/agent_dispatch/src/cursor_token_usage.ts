/** Cursor SDK 上报的会话用量。`inputTokens` 有时已含缓存命中。 */
export type CursorTokenUsage = {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  totalTokens?: number;
};

/** 与 Cursor Dashboard 分项一致、不重复累计的用量。 */
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
 * 把 SDK `TokenUsage` 收成 Dashboard 口径：
 * Input 为未缓存 prompt；Total = Input + Cache Read + Cache Write + Output。
 * SDK 若把缓存算进 input 又加进 total，这里会拆开，避免合并时翻倍。
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
