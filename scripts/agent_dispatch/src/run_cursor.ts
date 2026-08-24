import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import {
  Agent,
  Cursor,
  CursorAgentError,
  JsonlLocalAgentStore,
  type LocalAgentOptions,
} from "@cursor/sdk";
import { settleWithin } from "./async_limit.ts";
import type { WorkerCancellation } from "./cancellation.ts";
import { loadCursorMcpServers } from "./cursor_mcp_servers.ts";
import {
  CURSOR_WORKER_DISALLOWED_TOOLS,
  fallbackDisallowedTools,
} from "./cursor_disallowed_tools.ts";
import { installCursorSdkScanLogTap } from "./cursor_sdk_scan_log.ts";
import { CursorThinkingStream } from "./cursor_thinking_stream.ts";
import {
  formatSessionTokenLog,
  toDashboardTokenUsage,
} from "./cursor_token_usage.ts";
import {
  CursorShellSpanEmitter,
  isShellSpanEvent,
} from "./cursor_shell_spans.ts";
import {
  isSuccessfulDispatchTerminalStep,
  startPollingDispatchTerminal,
} from "./dispatch_terminal.ts";
import {
  AgentRunDiagnostics,
  formatAgentRunDiagnostics,
} from "./run_diagnostics.ts";
import { isRetryableError, withRetry } from "./retry.ts";
import { readyBlockedByShells } from "./verification_ready_gate.ts";
import {
  createAskUserTool,
  emitAssistantMessage,
  emitConversationSnapshot,
  emitSessionStart,
  emitThinkingMessage,
  sessionStartText,
} from "./interaction_bridge.ts";
import {
  extractConversationMessages,
  extractCursorAssistantStepText,
  extractCursorThinkingStepText,
  type ConversationTranscriptMessage,
} from "./assistant_text.ts";
import { buildConversationTranscript } from "./conversation_transcript.ts";
import {
  nextCursorSdkParamsAfterCreateError,
  selectCursorSdkModelParams,
  withCursorSdkCatalog,
  type DispatchResult,
  type ModelParam,
  type RoundDispatchJob,
} from "./types.ts";
import { type WorkerLogSource, workerLog } from "./worker_log.ts";

function logLine(line: string, source: WorkerLogSource = "worker"): void {
  workerLog(line, source);
}

function logLines(lines: string[], source: WorkerLogSource = "worker"): void {
  for (const line of lines) {
    logLine(line, source);
  }
}

function formatJson(value: unknown, max = 4000): string {
  if (value === undefined) return "";
  try {
    const text = JSON.stringify(value);
    if (text.length <= max) return text;
    return `${text.slice(0, max)}…`;
  } catch {
    return String(value);
  }
}

function expandMultiline(prefix: string, body: string): string[] {
  const lines = body
    .replace(/\s+$/, "")
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0);
  if (lines.length === 0) return [`${prefix}(empty)`];
  const result = [`${prefix}${lines[0]}`];
  for (let i = 1; i < lines.length; i++) {
    result.push(`  │ ${lines[i]}`);
  }
  return result;
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function pickString(message: Record<string, unknown> | undefined, ...keys: string[]): string {
  if (!message) return "";
  for (const key of keys) {
    const value = message[key];
    if (typeof value === "string" && value.trim()) return value;
  }
  return "";
}

function parseJsonRecord(value: unknown): Record<string, unknown> | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return undefined;
  try {
    return asRecord(JSON.parse(trimmed));
  } catch {
    return undefined;
  }
}

function usefulJson(value: unknown, max = 4000): string {
  if (value === undefined || value === null) return "";
  if (typeof value === "string") return value.trim();
  const text = formatJson(value, max);
  if (!text || text === "{}" || text === "[]" || text === "null") return "";
  return text;
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

function extractToolDetail(payload: Record<string, unknown> | undefined): string {
  if (!payload) return "";
  const nested =
    asRecord(payload.args) ??
    asRecord(payload.arguments) ??
    asRecord(payload.input) ??
    asRecord(payload.params) ??
    asRecord(asRecord(payload.function)?.arguments) ??
    parseJsonRecord(payload.args) ??
    parseJsonRecord(payload.arguments) ??
    parseJsonRecord(asRecord(payload.function)?.arguments);
  const command = pickString(
    payload,
    "command",
    "cmd",
    "shellCommand",
    "query",
    "pattern",
    "glob_pattern",
    "globPattern",
  );
  if (command) return command;
  if (nested) {
    const nestedCommand = pickString(
      nested,
      "command",
      "cmd",
      "shellCommand",
      "query",
      "pattern",
      "glob_pattern",
      "globPattern",
    );
    if (nestedCommand) {
      const extra = { ...nested };
      delete extra.command;
      delete extra.cmd;
      delete extra.shellCommand;
      const rest = usefulJson(extra, 2000);
      return rest ? `${nestedCommand}  ${rest}` : nestedCommand;
    }
    return usefulJson(nested);
  }
  const rawArgs = payload.args ?? payload.arguments ?? payload.input ?? payload.params;
  if (typeof rawArgs === "string" && rawArgs.trim()) return rawArgs.trim();
  return "";
}

function isShellTool(name: string): boolean {
  return /^(shell|bash|cmd|powershell|pwsh)$/i.test(name);
}

function describeStep(step: { type?: unknown; message?: unknown }): {
  lines: string[];
  source: WorkerLogSource;
  toolName?: string;
  detail?: string;
} {
  const record = asRecord(step) ?? {};
  const type = String(record.type ?? "unknown");
  const message = toolPayload(record);
  switch (type) {
    case "assistantMessage":
      return {
        lines: expandMultiline("Assistant: ", extractCursorAssistantStepText(record)),
        source: "ai",
      };
    case "thinkingMessage": {
      const text = pickString(message, "text", "thinking", "content");
      return {
        lines: text ? expandMultiline("Thinking: ", text) : [],
        source: "ai",
      };
    }
    case "toolCall": {
      const toolName =
        pickString(message, "name", "toolName", "functionName", "type") ||
        pickString(record, "name", "toolName") ||
        "tool";
      const detail = extractToolDetail(message);
      if (!detail) {
        return {
          lines: [`Tool: ${toolName}`],
          source: isShellTool(toolName) ? "shell" : "mcp",
          toolName,
        };
      }
      if (isShellTool(toolName)) {
        return {
          lines: expandMultiline("Command: ", detail),
          source: "shell",
          toolName,
          detail,
        };
      }
      return {
        lines: expandMultiline(`Tool: ${toolName} `, detail),
        source: "mcp",
        toolName,
        detail,
      };
    }
    case "toolResult": {
      const toolName = pickString(message, "name", "toolName", "type") || "tool";
      const result = message?.result ?? message?.output ?? message?.content ?? message?.text;
      if (result === undefined) {
        return { lines: [], source: "mcp" };
      }
      const body = typeof result === "string" ? result : formatJson(result);
      if (!String(body).trim()) return { lines: [], source: "mcp" };
      return {
        lines: expandMultiline(`Tool result: ${toolName} `, body),
        source: "mcp",
      };
    }
    case "shellConversationTurn":
    case "shell": {
      const command = extractToolDetail(message) || pickString(message, "command", "text");
      if (!command) return { lines: [], source: "shell" };
      return {
        lines: expandMultiline("Command: ", command),
        source: "shell",
      };
    }
    default: {
      const detail = message ? usefulJson(message, 800) : "";
      if (!detail) return { lines: [], source: "worker" };
      return {
        lines: [`Step: ${type} ${detail}`],
        source: "worker",
      };
    }
  }
}

function catalogParameterValues(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((item) => {
    if (typeof item === "string" && item.trim()) return [item.trim()];
    if (item && typeof item === "object" && "value" in item) {
      const text = String((item as { value?: unknown }).value ?? "").trim();
      return text ? [text] : [];
    }
    return [];
  });
}

async function attachLiveCursorModelCatalog(
  job: RoundDispatchJob,
  apiKey: string,
): Promise<RoundDispatchJob> {
  try {
    const models = await withRetry(
      "Fetch Cursor model catalog",
      () => Cursor.models.list({ apiKey }),
      { maxAttempts: 2, baseDelayMs: 400 },
    );
    const mapped = models.map((item) => ({
      id: item.id,
      parameters: (item.parameters ?? []).map((parameter) => ({
        id: parameter.id,
        values: catalogParameterValues(parameter.values),
      })),
    }));
    logLine(`Checked params with Cursor.models.list (${mapped.length} models)`);
    return withCursorSdkCatalog(job, mapped) as RoundDispatchJob;
  } catch (err) {
    logLine(
      `Failed to fetch the Cursor model catalog; using the workbench cache: ${err instanceof Error ? err.message : String(err)}`,
    );
    return job;
  }
}

export async function runCursor(
  job: RoundDispatchJob,
  cancellation?: WorkerCancellation,
): Promise<DispatchResult> {
  const apiKey = process.env.CURSOR_API_KEY?.trim();
  if (!apiKey) {
    return {
      ok: false,
      error: "Missing CURSOR_API_KEY (Dashboard → Integrations / API Keys)",
    };
  }

  const modelId = job.model?.trim() || "composer-2.5";
  const jobWithCatalog = await attachLiveCursorModelCatalog(job, apiKey);
  const selected = selectCursorSdkModelParams(jobWithCatalog);
  let params = selected.params;
  logLine(`Cursor model=${modelId} params=${JSON.stringify(params ?? [])}`);
  if (selected.dropped.length > 0) {
    logLine(
      `Not sent to the Cursor SDK: ${selected.dropped.join(", ")} (unsupported by the current model catalog, or a Kanban-only parameter).` +
        (selected.dropped.includes("fast")
          ? " This model has no fast; turning on fast mode will not apply."
          : ""),
    );
  }

  const agentMcpUrl = job.round.agentEndpointUrl.trim();
  if (!agentMcpUrl) {
    return { ok: false, error: "This claim is missing a scoped MCP endpoint" };
  }

  try {
    // Cursor SDK's built-in Shell inherits the Worker cwd; pin it to the
    // target repo before Agent.create so Shell does not land in the packaged
    // agent_worker directory.
    process.chdir(job.cwd);
    const startedAt = Date.now();
    let stepCount = 0;
    let toolCallCount = 0;
    const diagnostics = new AgentRunDiagnostics();
    const shellSpans = new CursorShellSpanEmitter();
    const live: ConversationTranscriptMessage[] = [];
    const askUserTool = createAskUserTool(job, cancellation, (text) => {
      live.push({ role: "user", text });
    });
    const storeDir = join(homedir(), ".cursor", "kanban-agent-jsonl-store");
    mkdirSync(storeDir, { recursive: true });
    const mcp = loadCursorMcpServers({
      cwd: job.cwd,
      scopedKanbanUrl: agentMcpUrl,
      projectMcpTags: job.round.projectMcpTags,
    });
    const localOptions: LocalAgentOptions = {
      cwd: job.cwd,
      // User Rules are already injected in full by the Worker. Enable `user`
      // so Cursor can pick user Skills by frontmatter triggers instead of
      // stuffing every Skill body into this card prompt. MCP stays explicit.
      settingSources: ["project", "user"],
      store: new JsonlLocalAgentStore(storeDir),
      ...(askUserTool ? { customTools: { ask_user: askUserTool } } : {}),
      // Headless Worker has nobody to click approve; Auto-review would block ready_to_submit.
      autoReview: false,
      sandboxOptions: { enabled: job.enableSandbox === true },
    };
    const createOptions = (modelParams?: ModelParam[]) => ({
      apiKey,
      model: {
        id: modelId,
        ...(modelParams && modelParams.length > 0 ? { params: modelParams } : {}),
      },
      mcpServers: mcp.servers,
      local: localOptions,
    });
    let disallowedTools = CURSOR_WORKER_DISALLOWED_TOOLS;
    let agent;
    const stopScanLog = installCursorSdkScanLogTap();
    let thinkingStream: CursorThinkingStream | undefined;
    try {
      try {
        agent = await Agent.create({
          ...createOptions(params),
          disallowedTools,
        });
      } catch (err) {
        const fallback = fallbackDisallowedTools(err);
        const stripped = nextCursorSdkParamsAfterCreateError(params, err);
        if (fallback == null && !stripped.changed) throw err;
        if (fallback != null) disallowedTools = fallback;
        if (stripped.changed) {
          params = stripped.params;
          logLine(
            `Cursor rejected params ${stripped.dropped.join(", ")}; dropped them and retrying session create.`,
          );
        }
        agent = await Agent.create({
          ...createOptions(params),
          disallowedTools,
        });
      }
      logLine(
        `Local run: JSONL store=${storeDir}; sandbox ${job.enableSandbox === true ? "on" : "off"}; ` +
          `merged MCP (${mcp.names.join(", ") || "none"}); ` +
          `kanbanMCP forced to scoped (${agentMcpUrl}); ` +
          `disallowed tools=${disallowedTools.join(",") || "none"}; ` +
          `settingSources=project,user (user and project Skills are selected by Cursor trigger conditions; ` +
            `user Rules are already injected by the Worker; MCP uses only the servers merged for this round)`,
      );
      logLine("Local session created; starting…");
      thinkingStream = new CursorThinkingStream();
      thinkingStream.notePromptSent();
      emitSessionStart(job);
      const sessionUser = sessionStartText(job);
      if (sessionUser) live.push({ role: "user", text: sessionUser });
      const emittedAssistant = new Set<string>();
      const emittedThinking = new Set<string>();
      const emitAssistant = (text: string): void => {
        const normalized = text.trim();
        if (!normalized || emittedAssistant.has(normalized)) return;
        emittedAssistant.add(normalized);
        live.push({ role: "assistant", text: normalized });
        emitAssistantMessage(job, normalized);
      };
      const emitThinking = (text: string): void => {
        const normalized = text.trim();
        if (!normalized || emittedThinking.has(normalized)) return;
        emittedThinking.add(normalized);
        live.push({ role: "thinking", text: normalized });
        emitThinkingMessage(job, normalized);
      };
      const flushSnapshot = (
        turns: readonly unknown[] = [],
        trailing?: string,
      ): void => {
        emitConversationSnapshot(
          job,
          buildConversationTranscript({
            sessionUser,
            live,
            fromTurns: extractConversationMessages(turns),
            trailingAssistant: trailing,
          }),
        );
      };
      let endedByTerminal = false;
      let runCancel: (() => Promise<void>) | undefined;
      let resolveTerminalReached: (() => void) | undefined;
      const terminalReached = new Promise<void>((resolve) => {
        resolveTerminalReached = resolve;
      });
      const stopAfterTerminal = (reason: string): void => {
        if (endedByTerminal) return;
        endedByTerminal = true;
        logLine(`Finalization tool succeeded (${reason}); ending the Cursor session`);
        resolveTerminalReached?.();
        void runCancel?.().catch(() => undefined);
      };
      const run = await agent.send({
        text: askUserTool
          ? `${job.prompt}\n\n## Board interaction\nWhen you need the user to confirm, supply missing requirements, or choose a plan, you MUST call ask_user; do not call askQuestion, and do not only list options in assistant prose. When there are 2–4 mutually exclusive options, you MUST pass choices; the board shows an option menu on the latest-run screen and waits for a reply.`
          : job.prompt,
        images: job.round.images,
      }, {
        mcpServers: mcp.servers,
        onDelta: ({ update }) => {
          thinkingStream?.handleDelta(update);
          const type =
            update && typeof update === "object" && "type" in update
              ? String((update as { type?: unknown }).type ?? "")
              : "";
          if (type === "thinking-completed" || type === "thinking") {
            emitThinking(thinkingStream?.assembledText() ?? "");
          }
        },
        onStep: async ({ step }) => {
          try {
            stepCount += 1;
            if (step.type === "toolCall") toolCallCount += 1;
            const described = describeStep(
              step as { type?: unknown; message?: unknown },
            );
            diagnostics.recordStep({
              type: String(step.type),
              toolName: described.toolName,
              detail: described.detail,
            });
            const skipThinkingDump =
              step.type === "thinkingMessage" &&
              thinkingStream?.consumeStreamedThinking() === true;
            if (!skipThinkingDump && described.lines.length > 0) {
              logLines(described.lines, described.source);
            }
            if (step.type === "thinkingMessage") {
              emitThinking(
                extractCursorThinkingStepText(step) ||
                  thinkingStream?.assembledText() ||
                  "",
              );
            }
            if (step.type === "assistantMessage") {
              emitAssistant(extractCursorAssistantStepText(step));
            }
          } catch {
            logLine("Received a progress step");
          }
          try {
            const event = shellSpans.observe(step, Date.now());
            if (isShellSpanEvent(event)) {
              await job.round.reportShellSpan?.(event);
            }
            if (job.terminateAfterDispatchTerminal !== false &&
                isSuccessfulDispatchTerminalStep(step)) {
              stopAfterTerminal("tool result");
            }
          } catch (err) {
            logLine(
              `Failed to report the Shell timeline: ${err instanceof Error ? err.message : String(err)}`,
            );
          }
        },
      });
      cancellation?.onCancel(() => {
        void run.cancel().catch(() => undefined);
      });
      runCancel = () => run.cancel();
      if (endedByTerminal) {
        void run.cancel().catch(() => undefined);
      }
      if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
        await run.cancel().catch(() => undefined);
      }
      const terminalPoll = job.terminateAfterDispatchTerminal === false
        ? { stop() {} }
        : startPollingDispatchTerminal(
          job.round.peekDispatchTerminal,
          (kind) => stopAfterTerminal(`MCP ${kind}`),
        );
      let result;
      let terminalEndedWithoutWait = false;
      try {
        const winner = await Promise.race([
          run.wait().then((value) => ({ kind: "result" as const, value })),
          terminalReached.then(() => ({ kind: "terminal" as const })),
        ]);
        if (winner.kind === "terminal") {
          terminalEndedWithoutWait = true;
          // After a normal terminal, do not wait for SDK cancel; give it a few seconds for usage.
          await settleWithin(3000, run.cancel());
          result = {
            id: run.id,
            status: "cancelled" as const,
            usage: run.usage,
          };
        } else {
          result = winner.value;
        }
      } finally {
        terminalPoll.stop();
      }
      let turns: unknown[] = [];
      if (!terminalEndedWithoutWait) {
        try {
          turns = await run.conversation();
          for (const message of extractConversationMessages(turns)) {
            if (message.role === "thinking") emitThinking(message.text);
            if (message.role === "assistant") emitAssistant(message.text);
          }
        } catch {
          // If the conversation snapshot is unavailable, fall back to result.result.
        }
      }
      if (typeof result.result === "string") {
        emitAssistant(result.result);
      }
      flushSnapshot(
        turns,
        typeof result.result === "string" ? result.result : undefined,
      );
      const metrics = diagnostics.snapshot();
      logLine(formatAgentRunDiagnostics(metrics));
      const cancellationReason =
        endedByTerminal
          ? "dispatch_terminal"
          : cancellation?.isSkipRequested
            ? "user_skip"
            : cancellation?.isCancelled
              ? "user_cancelled"
              : result.status === "cancelled"
                ? "sdk_cancelled"
                : undefined;
      logLine(
        `Cursor run id=${result.id} status=${result.status}` +
          (cancellationReason ? ` reason=${cancellationReason}` : "") +
          ` steps=${stepCount} tools=${toolCallCount} elapsedMs=${Date.now() - startedAt}`,
      );
      // Active finalization may omit usage on the SDK result; the run handle still has totals.
      const usage = result.usage ?? run.usage;
      if (usage && toDashboardTokenUsage(usage).totalTokens > 0) {
        logLine(formatSessionTokenLog(usage, metrics));
      }
      if (cancellation?.isSkipRequested) {
        logLine("Cursor session skipped by the user", "worker");
        return { ok: false, error: "Skipped" };
      }
      if (cancellation?.isCancelled && !endedByTerminal) {
        logLine("Cursor session stopped by the user", "worker");
        return { ok: false, error: "Cancelled" };
      }
      if (endedByTerminal) {
        const readyAt = shellSpans.lastReadyStartedAtMs();
        if (readyAt != null) {
          const blocked = readyBlockedByShells(shellSpans.snapshot(), readyAt);
          if (blocked) {
            logLine(blocked);
            return { ok: false, error: blocked };
          }
        }
        return {
          ok: true,
          summary:
            typeof result.result === "string"
              ? result.result
              : "Finalization tool succeeded; session ended",
        };
      }
      if (result.status === "cancelled") {
        logLine("Cursor session stopped by the user", "worker");
        return { ok: false, error: "Cancelled" };
      }
      if (result.status === "error") {
        return {
          ok: false,
          error: `Cursor run failed: ${result.error?.message ?? result.id}`,
          summary: typeof result.result === "string" ? result.result : undefined,
          retryable: isRetryableError(result.error),
        };
      }

      const readyAt = shellSpans.lastReadyStartedAtMs();
      if (readyAt != null) {
        const blocked = readyBlockedByShells(shellSpans.snapshot(), readyAt);
        if (blocked) {
          logLine(blocked);
          return { ok: false, error: blocked };
        }
      }

      const summary =
        typeof result.result === "string"
          ? result.result
          : result.status === "finished"
            ? "Cursor session finished"
            : `Cursor status: ${result.status}`;

      return { ok: result.status === "finished", summary };
    } finally {
      stopScanLog();
      if (agent) {
        const disposeMs =
          cancellation?.isCancelled || cancellation?.isSkipRequested ? 500 : 8000;
        await settleWithin(disposeMs, agent[Symbol.asyncDispose]());
      }
    }
  } catch (err) {
    if (cancellation?.isSkipRequested) {
      return { ok: false, error: "Skipped" };
    }
    if (cancellation?.isCancelled) {
      return { ok: false, error: "Cancelled" };
    }
    if (err instanceof CursorAgentError) {
      return {
        ok: false,
        error: `Cursor failed to start: ${err.message} (retryable=${err.isRetryable})`,
        // The SDK sometimes marks a dropped connection as non-retryable; keep a local network fallback.
        retryable: err.isRetryable || isRetryableError(err),
      };
    }
    return {
      ok: false,
      error: `Cursor session error: ${err instanceof Error ? err.message : String(err)}`,
      retryable: isRetryableError(err),
    };
  }
}
