import { sleep } from "./retry.ts";

export const DISPATCH_TERMINAL_TOOL_NAMES = [
  "ready_to_submit",
  "submit_consultation",
  "block_card",
] as const;

export type DispatchTerminalKind = "none" | "declared" | "verify" | "blocked";

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

export function dispatchTerminalToolName(step: unknown): string | undefined {
  const record = asRecord(step);
  if (!record) return undefined;
  const message = toolPayload(record);
  const nested =
    asRecord(message?.args) ??
    asRecord(message?.arguments) ??
    asRecord(message?.input) ??
    asRecord(message?.params);
  const name =
    pickString(message, "toolName", "name") ||
    pickString(nested, "toolName", "name");
  const type = pickString(message, "type") || pickString(record, "type");
  if (DISPATCH_TERMINAL_TOOL_NAMES.includes(name as (typeof DISPATCH_TERMINAL_TOOL_NAMES)[number])) {
    return name;
  }
  if (type === "mcp") {
    const nestedName = pickString(nested, "toolName", "name");
    if (
      DISPATCH_TERMINAL_TOOL_NAMES.includes(
        nestedName as (typeof DISPATCH_TERMINAL_TOOL_NAMES)[number],
      )
    ) {
      return nestedName;
    }
  }
  return undefined;
}

function resultLooksFailed(result: Record<string, unknown>): boolean {
  const status = String(result.status ?? "").toLowerCase();
  if (status === "error" || status === "failed") return true;
  if (result.isError === true) return true;
  const value = asRecord(result.value) ?? result;
  if (value.ok === false) return true;
  return false;
}

function resultLooksSuccess(result: Record<string, unknown>): boolean {
  if (resultLooksFailed(result)) return false;
  const status = String(result.status ?? "").toLowerCase();
  if (status === "success" || status === "ok" || status === "completed") {
    return true;
  }
  const value = asRecord(result.value) ?? result;
  return value.ok === true;
}

/** MCP 收尾工具已返回成功（不是开始调用）。 */
export function isSuccessfulDispatchTerminalStep(step: unknown): boolean {
  if (!dispatchTerminalToolName(step)) return false;
  const record = asRecord(step);
  const message = record ? toolPayload(record) : undefined;
  const result = asRecord(message?.result) ?? asRecord(message?.output);
  if (!result) return false;
  return resultLooksSuccess(result);
}

export function dispatchTerminalFromSession(
  status: unknown,
  card?: unknown,
): DispatchTerminalKind {
  const pending = asRecord(asRecord(status)?.pending);
  if (String(pending?.status ?? "") === "declared") return "declared";
  const record = asRecord(card);
  if (!record) return "none";
  const columnId = String(record.columnId ?? "");
  const columnName = String(record.columnName ?? "");
  if (columnId === "verify" || columnName === "待验证") return "verify";
  if (columnId === "blocked" || columnName === "阻塞中") return "blocked";
  return "none";
}

export function startPollingDispatchTerminal(
  peek: (() => Promise<DispatchTerminalKind>) | undefined,
  onHit: (kind: DispatchTerminalKind) => void,
  intervalMs = 750,
): { stop(): void } {
  if (!peek) return { stop() {} };
  let stopped = false;
  const tick = async (): Promise<void> => {
    while (!stopped) {
      try {
        const kind = await peek();
        if (kind !== "none") {
          onHit(kind);
          return;
        }
      } catch {
        // 轮询失败不中断会话；下一拍再试。
      }
      await sleep(intervalMs);
    }
  };
  void tick();
  return {
    stop() {
      stopped = true;
    },
  };
}
