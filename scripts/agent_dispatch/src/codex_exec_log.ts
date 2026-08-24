import { formatSessionTokenLog } from "./cursor_token_usage.ts";
import type { WorkerLogLevel, WorkerLogRecord, WorkerLogSource } from "./worker_log.ts";
import { extractAssistantText } from "./assistant_text.ts";

const OUTPUT_CLIP = 4000;
const JSON_CLIP = 2000;
const ANSI_PATTERN = /\x1B\[[0-9;]*m/g;
const DIAGNOSTIC_PATTERN =
  /^\s*(?:warning:|error:|fatal:|WARN\b|ERROR\b|FATAL\b)/i;
const RECONNECT_PATTERN = /reconnecting\.\.\.\s*\d+\s*\/\s*\d+/i;

export type CodexTtyRole = "none" | "user" | "codex" | "exec" | "patch";

export type CodexLogState = {
  jsonSeen: boolean;
  ttyRole: CodexTtyRole;
  ttyExecAwaitingCommand: boolean;
  ttyAwaitingTokenCount: boolean;
};

export function createCodexLogState(): CodexLogState {
  return {
    jsonSeen: false,
    ttyRole: "none",
    ttyExecAwaitingCommand: false,
    ttyAwaitingTokenCount: false,
  };
}

export function createLineBuffer(onLine: (line: string) => void): {
  push(chunk: Buffer | string): void;
  flush(): void;
} {
  let pending = "";
  return {
    push(chunk: Buffer | string): void {
      pending += typeof chunk === "string" ? chunk : chunk.toString("utf8");
      pending = pending.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
      let index = pending.indexOf("\n");
      while (index >= 0) {
        onLine(pending.slice(0, index));
        pending = pending.slice(index + 1);
        index = pending.indexOf("\n");
      }
    },
    flush(): void {
      if (pending.length > 0) onLine(pending);
      pending = "";
    },
  };
}

/** \u89E3\u6790 Codex `--json` \u7684\u4E00\u884C JSONL，\u6309\u4E8B\u4EF6\u7C7B\u578B\u6620\u5C04\u6210\u4E0E Cursor \u76F8\u540C\u7684\u6765\u6E90/\u7EA7\u522B。 */
export function recordsFromCodexJsonLine(
  raw: string,
  state: CodexLogState,
): WorkerLogRecord[] {
  const line = stripAnsi(raw).trim();
  if (!line) return [];
  if (!line.startsWith("{")) {
    return recordsFromCodexStderrLine(line, state);
  }
  let event: Record<string, unknown>;
  try {
    event = asRecord(JSON.parse(line)) ?? {};
  } catch {
    return withDefaultLevel([{ line: clip(line, 200), source: "worker" }]);
  }
  state.jsonSeen = true;
  return recordsFromCodexEvent(event);
}

/** \u5904\u7406 Codex stderr：JSON \u5DF2\u63A5\u901A\u65F6\u53EA\u4FDD\u7559\u8BCA\u65AD\u884C，\u5426\u5219\u6309 TTY \u89D2\u8272\u56DE\u9000\u5206\u7C7B。 */
export function recordsFromCodexStderrLine(
  raw: string,
  state: CodexLogState,
): WorkerLogRecord[] {
  const line = stripAnsi(raw).replace(/\s+$/, "");
  if (!line.trim()) return [];
  const diagnostic = diagnosticRecord(line, "worker");
  if (state.jsonSeen) return withDefaultLevel(diagnostic ? [diagnostic] : []);
  return withDefaultLevel(recordsFromCodexTtyLine(line, state));
}

export function recordsFromCodexEvent(
  event: Record<string, unknown>,
): WorkerLogRecord[] {
  return withDefaultLevel(recordsFromCodexEventInner(event));
}

function recordsFromCodexEventInner(
  event: Record<string, unknown>,
): WorkerLogRecord[] {
  const type = String(event.type ?? "");
  switch (type) {
    case "thread.started": {
      const threadId = pickString(event, "thread_id");
      return threadId
        ? [{ line: `Codex session ${threadId}`, source: "worker" }]
        : [];
    }
    case "turn.started":
      return [];
    case "turn.completed":
      return recordsFromUsage(asRecord(event.usage));
    case "turn.failed": {
      const message =
        pickString(asRecord(event.error), "message") ||
        pickString(event, "message") ||
        "Codex turn failed";
      return [{ line: message, source: "worker", level: "error" }];
    }
    case "error": {
      const message = pickString(event, "message") || "Codex error";
      if (RECONNECT_PATTERN.test(message)) {
        return [{ line: message, source: "worker" }];
      }
      return [{ line: message, source: "worker", level: "error" }];
    }
    case "item.started":
    case "item.updated":
    case "item.completed":
      return recordsFromCodexItem(type, asRecord(event.item) ?? {});
    default:
      return [];
  }
}

function recordsFromCodexItem(
  eventType: string,
  item: Record<string, unknown>,
): WorkerLogRecord[] {
  const itemType = String(item.type ?? item.item_type ?? "");
  const status = String(item.status ?? "");
  const failed = status === "failed" || eventType === "item.failed";
  switch (itemType) {
    case "agent_message":
    case "assistant_message":
      if (eventType !== "item.completed") return [];
      return toRecords(
        expandMultiline("Assistant: ", extractAssistantText(item) || pickString(item, "text")),
        "ai",
      );
    case "reasoning":
      if (eventType !== "item.completed") return [];
      return toRecords(expandMultiline("Thinking: ", pickString(item, "text")), "ai");
    case "command_execution":
      return recordsFromCommand(
        eventType,
        item,
        commandExecutionOutcome(eventType, item, status),
      );
    case "file_change":
      if (eventType !== "item.completed") return [];
      return recordsFromFileChange(item, failed);
    case "mcp_tool_call":
      return recordsFromMcp(eventType, item, failed);
    case "web_search":
      if (eventType !== "item.completed") return [];
      return pickString(item, "query")
        ? [{ line: `Tool: web_search ${pickString(item, "query")}`, source: "mcp" }]
        : [];
    case "todo_list":
      return recordsFromTodo(item);
    case "error":
      if (eventType !== "item.completed") return [];
      return [
        {
          line: pickString(item, "message") || "Codex non-fatal warning",
          source: "worker",
          level: "warning",
        },
      ];
    default:
      return [];
  }
}

type CommandExecutionOutcome = "success" | "no_match" | "search_issue" | "failed";

function commandExecutionOutcome(
  eventType: string,
  item: Record<string, unknown>,
  status: string,
): CommandExecutionOutcome {
  if (eventType === "item.failed") return "failed";
  const exitCode = item.exit_code;
  if (typeof exitCode === "number" && Number.isFinite(exitCode)) {
    if (exitCode === 0) return "success";
    if (isRipgrepCommand(pickString(item, "command"))) {
      // rg uses 1 for a normal no-match result and 2 for a bad path/regex.
      return exitCode === 1 ? "no_match" : "search_issue";
    }
    return "failed";
  }
  return status === "failed" ? "failed" : "success";
}

function recordsFromCommand(
  eventType: string,
  item: Record<string, unknown>,
  outcome: CommandExecutionOutcome,
): WorkerLogRecord[] {
  const command = pickString(item, "command");
  if (eventType === "item.started") {
    return command ? toRecords(expandMultiline("Command: ", command), "shell") : [];
  }
  if (eventType !== "item.completed") return [];
  const records: WorkerLogRecord[] = [];
  const failed = outcome === "failed";
  const searchIssue = outcome === "search_issue";
  if (command && outcome === "no_match") {
    records.push({
      line: `Search had no matches: ${clip(command, JSON_CLIP)}`,
      source: "shell",
    });
  } else if (command && searchIssue) {
    records.push({
      line: `Search command issue (task not interrupted): ${clip(command, JSON_CLIP)}`,
      source: "shell",
      level: "warning",
    });
  } else if (command && failed) {
    records.push({
      line: `Command failed: ${clip(command, JSON_CLIP)}`,
      source: "shell",
      level: "error",
    });
  }
  const output = pickString(item, "aggregated_output");
  if ((failed || searchIssue) && output.trim()) {
    records.push(
      ...toRecords(
        expandMultiline("Command output: ", clip(output, OUTPUT_CLIP)),
        "shell",
        failed ? "error" : "warning",
      ),
    );
  }
  records.push(...diagnosticRecordsFromOutput(output, "shell"));
  return records;
}

function isRipgrepCommand(command: string): boolean {
  return /(?:^|[\s;&|"'])rg(?:\.exe)?(?:\s|$)/i.test(command);
}

function recordsFromFileChange(
  item: Record<string, unknown>,
  failed: boolean,
): WorkerLogRecord[] {
  const changes = Array.isArray(item.changes) ? item.changes : [];
  const parts = changes
    .map((entry) => asRecord(entry))
    .filter((entry): entry is Record<string, unknown> => entry != null)
    .map((entry) => {
      const path = pickString(entry, "path");
      if (!path) return "";
      const kind = String(entry.kind ?? "update");
      const label =
        kind === "add" ? "added" : kind === "delete" ? "deleted" : "updated";
      return `${label} ${path}`;
    })
    .filter(Boolean);
  const detail = parts.join("; ") || "apply_patch";
  return [
    {
      line: `Tool: apply_patch ${detail}`,
      source: "mcp",
      level: failed ? "error" : "info",
    },
  ];
}

function recordsFromMcp(
  eventType: string,
  item: Record<string, unknown>,
  failed: boolean,
): WorkerLogRecord[] {
  const tool = pickString(item, "tool") || "tool";
  if (eventType === "item.started") {
    const args = usefulJson(item.arguments);
    const detail = args ? `${tool} ${args}` : `${tool} started`;
    return [{ line: `Tool: ${detail}`, source: "mcp" }];
  }
  if (eventType !== "item.completed") return [];
  if (failed) {
    const err =
      pickString(asRecord(item.error), "message") ||
      pickString(item, "error") ||
      "call failed";
    return [
      {
        line: `Tool failed: ${tool} ${err}`,
        source: "mcp",
        level: "error",
      },
    ];
  }
  const result = mcpResultText(item.result);
  if (!result.trim()) return [];
  return toRecords(expandMultiline(`Tool result: ${tool} `, result), "mcp");
}

function recordsFromTodo(item: Record<string, unknown>): WorkerLogRecord[] {
  const items = Array.isArray(item.items) ? item.items : [];
  const parts = items
    .map((entry) => asRecord(entry))
    .filter((entry): entry is Record<string, unknown> => entry != null)
    .map((entry) => {
      const text = pickString(entry, "text");
      if (!text) return "";
      return `${entry.completed === true ? "✓ " : ""}${text}`;
    })
    .filter(Boolean);
  if (parts.length === 0) return [];
  return [{ line: `Plan: ${parts.join("; ")}`, source: "worker" }];
}

function recordsFromUsage(
  usage: Record<string, unknown> | undefined,
): WorkerLogRecord[] {
  if (!usage) return [];
  const cached = asCount(usage.cached_input_tokens);
  const inputRaw = asCount(usage.input_tokens);
  const input = cached > 0 && inputRaw >= cached ? inputRaw - cached : inputRaw;
  const output = asCount(usage.output_tokens);
  if (input + output + cached <= 0) return [];
  return [
    {
      line: formatSessionTokenLog({
        inputTokens: input,
        outputTokens: output,
        cacheReadTokens: cached,
      }),
      source: "worker",
    },
  ];
}

function recordsFromCodexTtyLine(
  line: string,
  state: CodexLogState,
): WorkerLogRecord[] {
  const trimmed = line.trim();
  const role = ttyRoleOf(trimmed);
  if (role) {
    state.ttyRole = role;
    state.ttyExecAwaitingCommand = role === "exec";
    state.ttyAwaitingTokenCount = trimmed === "tokens used";
    if (trimmed.startsWith("mcp:")) return recordsFromTtyMcp(trimmed);
    if (trimmed === "apply patch") {
      return [{ line: "Tool: apply_patch", source: "mcp" }];
    }
    if (trimmed === "patch: completed") {
      return [{ line: "Tool result: apply_patch", source: "mcp" }];
    }
    if (trimmed === "tokens used") return [];
    return [];
  }
  if (state.ttyAwaitingTokenCount) {
    state.ttyAwaitingTokenCount = false;
    const total = Number(trimmed.replace(/,/g, ""));
    if (Number.isFinite(total) && total > 0) {
      return [{ line: `Codex tokens used：${trimmed}`, source: "worker" }];
    }
  }
  if (isBannerLine(trimmed)) {
    return [{ line: trimmed, source: "worker" }];
  }
  if (state.ttyRole === "user") return [];
  if (state.ttyRole === "codex") {
    return toRecords(expandMultiline("Assistant: ", line), "ai");
  }
  if (state.ttyRole === "exec") {
    if (state.ttyExecAwaitingCommand) {
      state.ttyExecAwaitingCommand = false;
      return toRecords(expandMultiline("Command: ", trimmed), "shell");
    }
    if (/^failed in /i.test(trimmed) || /^error in /i.test(trimmed)) {
      return [{ line: `Command failed: ${trimmed}`, source: "shell", level: "error" }];
    }
    const diagnostic = diagnosticRecord(trimmed, "shell");
    return diagnostic ? [diagnostic] : [];
  }
  if (state.ttyRole === "patch") {
    if (trimmed.startsWith("diff ") || trimmed.startsWith("index ")) return [];
    if (/^[+-]/.test(trimmed) || trimmed.startsWith("@@")) return [];
    if (/^[A-Za-z]:\\/.test(trimmed) || trimmed.includes("/")) {
      return [{ line: `Tool result: apply_patch ${trimmed}`, source: "mcp" }];
    }
    return [];
  }
  const diagnostic = diagnosticRecord(trimmed, "worker");
  if (diagnostic) return [diagnostic];
  return [{ line: trimmed, source: "worker" }];
}

function ttyRoleOf(trimmed: string): CodexTtyRole | undefined {
  if (trimmed === "user") return "user";
  if (trimmed === "codex") return "codex";
  if (trimmed === "exec") return "exec";
  if (trimmed === "apply patch" || trimmed === "patch: completed") return "patch";
  if (trimmed === "tokens used") return "none";
  if (trimmed.startsWith("mcp:")) return "none";
  return undefined;
}

function recordsFromTtyMcp(line: string): WorkerLogRecord[] {
  const match = /^mcp:\s*([^/]+)\/(\S+)\s+(started|\(completed\))$/.exec(line);
  if (!match) return [{ line: `Tool: ${line.slice(4).trim()}`, source: "mcp" }];
  const tool = match[2]!;
  if (match[3] === "started") {
    return [{ line: `Tool: ${tool} started`, source: "mcp" }];
  }
  return [{ line: `Tool result: ${tool} done`, source: "mcp" }];
}

function isBannerLine(line: string): boolean {
  return (
    line.startsWith("OpenAI Codex") ||
    line === "--------" ||
    /^(workdir|model|provider|approval|sandbox|reasoning effort|reasoning summaries|session id):/i.test(
      line,
    )
  );
}

function diagnosticRecordsFromOutput(
  output: string,
  source: WorkerLogSource,
): WorkerLogRecord[] {
  if (!output.trim()) return [];
  const records: WorkerLogRecord[] = [];
  const seen = new Set<string>();
  for (const line of output.split(/\r?\n/)) {
    const record = diagnosticRecord(stripAnsi(line), source);
    if (!record || seen.has(record.line)) continue;
    seen.add(record.line);
    records.push(record);
  }
  return records;
}

function withDefaultLevel(records: WorkerLogRecord[]): WorkerLogRecord[] {
  return records.map((record) => ({
    ...record,
    level: record.level ?? "info",
  }));
}

function diagnosticRecord(
  line: string,
  source: WorkerLogSource,
): WorkerLogRecord | undefined {
  const trimmed = line.trim();
  if (!DIAGNOSTIC_PATTERN.test(trimmed)) return undefined;
  if (looksLikeDartNamedArgument(trimmed)) return undefined;
  const level: WorkerLogLevel = /^\s*(?:warning:|WARN\b)/i.test(trimmed)
    ? "warning"
    : "error";
  return { line: trimmed, source, level };
}

/** \u6E90\u7801\u91CC\u7684\u547D\u540D\u53C2\u6570（error: e, / error: '...'）\u4E0D\u662F git/\u7F16\u8BD1\u5668\u8BCA\u65AD。 */
function looksLikeDartNamedArgument(line: string): boolean {
  return /^\s*error:\s*(?:[A-Za-z_]\w*|'[^']*'|"[^"]*")\s*,?\s*$/.test(line);
}

function expandMultiline(prefix: string, body: string): string[] {
  const lines = body
    .replace(/\s+$/, "")
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0);
  if (lines.length === 0) {
    return prefix.endsWith(" ") || prefix.endsWith("：") ? [] : [prefix];
  }
  const result = [`${prefix}${lines[0]}`];
  for (let i = 1; i < lines.length; i++) {
    result.push(`  │ ${lines[i]}`);
  }
  return result;
}

function toRecords(
  lines: string[],
  source: WorkerLogSource,
  level: WorkerLogLevel = "info",
): WorkerLogRecord[] {
  return lines.map((line) => ({ line, source, level }));
}

function mcpResultText(result: unknown): string {
  const record = asRecord(result);
  if (!record) return usefulJson(result);
  const content = record.content;
  if (Array.isArray(content)) {
    const texts = content
      .map((block) => asRecord(block))
      .filter((block): block is Record<string, unknown> => block != null)
      .filter((block) => block.type === "text" && typeof block.text === "string")
      .map((block) => String(block.text).trim())
      .filter(Boolean);
    if (texts.length > 0) return clip(texts.join("\n"), OUTPUT_CLIP);
  }
  return usefulJson(record.structured_content ?? result);
}

function usefulJson(value: unknown, max = JSON_CLIP): string {
  if (value === undefined || value === null) return "";
  if (typeof value === "string") return clip(value.trim(), max);
  try {
    const text = JSON.stringify(value);
    if (!text || text === "{}" || text === "[]" || text === "null") return "";
    return clip(text, max);
  } catch {
    return clip(String(value), max);
  }
}

function pickString(
  record: Record<string, unknown> | undefined,
  key: string,
): string {
  const value = record?.[key];
  return typeof value === "string" ? value : "";
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function asCount(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.trunc(value));
}

function clip(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max)}…`;
}

function stripAnsi(text: string): string {
  return text.replace(ANSI_PATTERN, "");
}
