import type { ShellSpan } from "./verification_ready_gate.ts";

export type ShellSpanEvent = ShellSpan & {
  phase: "start" | "end";
};

export type ReadySubmitEvent = {
  kind: "ready";
  startedAtMs: number;
};

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function pickString(
  record: Record<string, unknown> | undefined,
  ...keys: string[]
): string {
  if (!record) return "";
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.trim()) return value.trim();
    if (typeof value === "number" && Number.isFinite(value)) return String(value);
  }
  return "";
}

function pickNumber(
  record: Record<string, unknown> | undefined,
  ...keys: string[]
): number | undefined {
  if (!record) return undefined;
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "number" && Number.isFinite(value)) {
      return Math.trunc(value);
    }
  }
  return undefined;
}

function isShellName(name: string): boolean {
  return /^(shell|bash|cmd|powershell|pwsh)$/i.test(name);
}

/** SDK 的 call_id 经常是 `call_…\nfc_…` 两行；MCP JSON 需要单行 id。 */
export function normalizeDispatchCallId(callId: string | undefined): string {
  return (callId ?? "")
    .trim()
    .split(/\s+/)
    .filter((part) => part.length > 0)
    .join("_");
}

/** 与 `run_cursor.ts` 的 toolPayload 对齐，覆盖 SDK 多种 step 形态。 */
function toolPayload(step: Record<string, unknown>): Record<string, unknown> | undefined {
  return (
    asRecord(step.message) ??
    asRecord(step.toolCall) ??
    asRecord(step.call) ??
    asRecord(step.tool) ??
    asRecord(asRecord(step.message)?.toolCall) ??
    asRecord(asRecord(step.message)?.call)
  );
}

function extractCommand(message: Record<string, unknown>): string {
  const nested =
    asRecord(message.args) ??
    asRecord(message.arguments) ??
    asRecord(message.input) ??
    asRecord(message.params);
  return (
    pickString(message, "command", "cmd", "shellCommand") ||
    pickString(nested, "command", "cmd", "shellCommand")
  );
}

function extractResult(message: Record<string, unknown>): {
  executionTimeMs?: number;
  exitCode?: number;
} | undefined {
  const result =
    asRecord(message.result) ??
    asRecord(message.output) ??
    asRecord(message.value);
  if (!result) return undefined;
  const value = asRecord(result.value) ?? result;
  const executionTimeMs = pickNumber(
    value,
    "executionTime",
    "executionTimeMs",
    "execution_time_ms",
  );
  const exitCode = pickNumber(value, "exitCode", "exit_code");
  if (executionTimeMs == null && exitCode == null && asRecord(message.result) == null) {
    return undefined;
  }
  return { executionTimeMs, exitCode };
}

function extractCallId(
  record: Record<string, unknown>,
  message: Record<string, unknown> | undefined,
): string {
  return normalizeDispatchCallId(
    pickString(message, "call_id", "callId", "id") ||
      pickString(record, "call_id", "callId"),
  );
}

export function isReadyToSubmitStep(step: unknown): boolean {
  const record = asRecord(step);
  if (!record) return false;
  const message = toolPayload(record);
  const nested =
    asRecord(message?.args) ??
    asRecord(message?.arguments);
  const toolName =
    pickString(message, "toolName", "name") ||
    pickString(nested, "toolName", "name");
  const type = pickString(message, "type") || pickString(record, "type");
  if (toolName === "ready_to_submit") return true;
  return type === "mcp" && pickString(nested, "toolName") === "ready_to_submit";
}

export function isShellSpanEvent(
  event: ShellSpanEvent | ReadySubmitEvent | undefined,
): event is ShellSpanEvent {
  if (!event || !("phase" in event)) return false;
  return (
    (event.phase === "start" || event.phase === "end") &&
    normalizeDispatchCallId(event.callId).length > 0
  );
}

export function toShellSpanReportPayload(input: {
  workerToken: string;
  sessionId: string;
  span: ShellSpanEvent;
}): Record<string, unknown> {
  const workerToken = input.workerToken.trim();
  const sessionId = input.sessionId.trim();
  const callId = normalizeDispatchCallId(input.span.callId);
  const phase = input.span.phase;
  const missing = [
    !workerToken ? "workerToken" : "",
    !sessionId ? "sessionId" : "",
    !callId ? "callId" : "",
    phase !== "start" && phase !== "end" ? "phase" : "",
  ].filter(Boolean);
  if (missing.length > 0) {
    throw new Error(`上报 Shell 时间线缺少 ${missing.join("、")}`);
  }
  return {
    workerToken,
    sessionId,
    callId,
    command: input.span.command ?? "",
    phase,
    startedAtMs: input.span.startedAtMs,
    ...(input.span.endedAtMs != null ? { endedAtMs: input.span.endedAtMs } : {}),
    ...(input.span.executionTimeMs != null
      ? { executionTimeMs: input.span.executionTimeMs }
      : {}),
    ...(input.span.exitCode != null ? { exitCode: input.span.exitCode } : {}),
  };
}

export class CursorShellSpanEmitter {
  private readonly open = new Map<string, ShellSpan>();
  private readonly spans = new Map<string, ShellSpan>();
  private seq = 0;
  private lastReadyAtMs: number | undefined;

  observe(step: unknown, nowMs: number): ShellSpanEvent | ReadySubmitEvent | undefined {
    const record = asRecord(step);
    if (!record) return undefined;
    if (isReadyToSubmitStep(record)) {
      const message = toolPayload(record);
      const hasResult = asRecord(message?.result) != null;
      if (!hasResult) this.lastReadyAtMs = nowMs;
      return { kind: "ready", startedAtMs: nowMs };
    }
    const message = toolPayload(record);
    if (!message) return undefined;
    const name =
      pickString(message, "name", "toolName", "functionName", "type") ||
      pickString(record, "name", "toolName");
    const type = pickString(record, "type") || pickString(message, "type");
    if (
      !isShellName(name) &&
      type !== "shell" &&
      pickString(message, "type") !== "shell"
    ) {
      return undefined;
    }
    const command = extractCommand(message);
    const callId = extractCallId(record, message);
    const result = extractResult(message);
    const isEnd = result != null || type === "toolResult";
    if (isEnd) {
      const open =
        (callId ? this.open.get(callId) : undefined) ??
        [...this.open.values()].find((item) => item.command === command) ??
        [...this.open.values()].at(-1);
      if (open) this.open.delete(open.callId);
      const span: ShellSpan = {
        callId: open?.callId || callId || `end-${this.seq++}`,
        command: command || open?.command || "",
        startedAtMs: open?.startedAtMs ?? nowMs,
        endedAtMs: nowMs,
        executionTimeMs: result?.executionTimeMs,
        exitCode: result?.exitCode,
      };
      this.spans.set(span.callId, span);
      return { ...span, phase: "end" };
    }
    const id = callId || `shell-${this.seq++}`;
    const span: ShellSpan = {
      callId: id,
      command,
      startedAtMs: nowMs,
    };
    this.open.set(id, span);
    this.spans.set(id, span);
    return { ...span, phase: "start" };
  }

  snapshot(): ShellSpan[] {
    return [...this.spans.values()];
  }

  lastReadyStartedAtMs(): number | undefined {
    return this.lastReadyAtMs;
  }
}
