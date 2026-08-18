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

function toolMessage(step: Record<string, unknown>): Record<string, unknown> | undefined {
  return (
    asRecord(step.message) ??
    asRecord(step.toolCall) ??
    asRecord(step.call)
  );
}

function extractCommand(message: Record<string, unknown>): string {
  const nested =
    asRecord(message.args) ??
    asRecord(message.arguments) ??
    asRecord(message.input);
  return (
    pickString(message, "command", "cmd", "shellCommand") ||
    pickString(nested, "command", "cmd", "shellCommand")
  );
}

function extractResult(message: Record<string, unknown>): {
  executionTimeMs?: number;
  exitCode?: number;
} | undefined {
  const result = asRecord(message.result);
  if (!result) return undefined;
  const value = asRecord(result.value) ?? result;
  return {
    executionTimeMs: pickNumber(value, "executionTime", "executionTimeMs"),
    exitCode: pickNumber(value, "exitCode"),
  };
}

export function isReadyToSubmitStep(step: unknown): boolean {
  const record = asRecord(step);
  if (!record) return false;
  const message = toolMessage(record);
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

export class CursorShellSpanEmitter {
  private readonly open = new Map<string, ShellSpan>();
  private readonly spans = new Map<string, ShellSpan>();
  private seq = 0;
  private lastReadyAtMs: number | undefined;

  observe(step: unknown, nowMs: number): ShellSpanEvent | ReadySubmitEvent | undefined {
    const record = asRecord(step);
    if (!record) return undefined;
    if (isReadyToSubmitStep(record)) {
      const message = toolMessage(record);
      const hasResult = asRecord(message?.result) != null;
      if (!hasResult) this.lastReadyAtMs = nowMs;
      return { kind: "ready", startedAtMs: nowMs };
    }
    const message = toolMessage(record);
    if (!message) return undefined;
    const name =
      pickString(message, "name", "toolName", "type") ||
      pickString(record, "name", "toolName");
    if (!isShellName(name) && pickString(message, "type") !== "shell") {
      return undefined;
    }
    const command = extractCommand(message);
    const callId =
      pickString(message, "call_id", "callId", "id") ||
      pickString(record, "call_id", "callId") ||
      "";
    const result = extractResult(message);
    if (result) {
      const open =
        (callId ? this.open.get(callId) : undefined) ??
        [...this.open.values()].find((item) => item.command === command) ??
        [...this.open.values()].at(-1);
      if (open) this.open.delete(open.callId);
      const span: ShellSpan = {
        callId: open?.callId ?? callId ?? `end-${this.seq++}`,
        command: command || open?.command || "",
        startedAtMs: open?.startedAtMs ?? nowMs,
        endedAtMs: nowMs,
        executionTimeMs: result.executionTimeMs,
        exitCode: result.exitCode,
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
