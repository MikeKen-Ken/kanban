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
import {
  formatSessionTokenLog,
  toDashboardTokenUsage,
} from "./cursor_token_usage.ts";
import {
  CursorShellSpanEmitter,
  isShellSpanEvent,
} from "./cursor_shell_spans.ts";
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
  sessionStartText,
} from "./interaction_bridge.ts";
import {
  extractConversationMessages,
  extractCursorAssistantStepText,
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
  if (lines.length === 0) return [`${prefix}（空）`];
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
        lines: expandMultiline("助手：", extractCursorAssistantStepText(record)),
        source: "ai",
      };
    case "thinkingMessage": {
      const text = pickString(message, "text", "thinking", "content");
      return {
        lines: text ? expandMultiline("思考：", text) : [],
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
          lines: [`工具：${toolName}`],
          source: isShellTool(toolName) ? "shell" : "mcp",
          toolName,
        };
      }
      if (isShellTool(toolName)) {
        return {
          lines: expandMultiline("命令：", detail),
          source: "shell",
          toolName,
          detail,
        };
      }
      return {
        lines: expandMultiline(`工具：${toolName} `, detail),
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
        lines: expandMultiline(`工具结果：${toolName} `, body),
        source: "mcp",
      };
    }
    case "shellConversationTurn":
    case "shell": {
      const command = extractToolDetail(message) || pickString(message, "command", "text");
      if (!command) return { lines: [], source: "shell" };
      return {
        lines: expandMultiline("命令：", command),
        source: "shell",
      };
    }
    default: {
      const detail = message ? usefulJson(message, 800) : "";
      if (!detail) return { lines: [], source: "worker" };
      return {
        lines: [`步骤：${type} ${detail}`],
        source: "worker",
      };
    }
  }
}

function assistantTextsFromTurns(turns: readonly unknown[]): string[] {
  return extractConversationMessages(turns)
    .filter((item) => item.role === "assistant")
    .map((item) => item.text);
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
      "拉取 Cursor 模型目录",
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
    logLine(`已用 Cursor.models.list 核对参数（${mapped.length} 个模型）`);
    return withCursorSdkCatalog(job, mapped) as RoundDispatchJob;
  } catch (err) {
    logLine(
      `拉取 Cursor 模型目录失败，改用工作台缓存：${err instanceof Error ? err.message : String(err)}`,
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
      error: "缺少环境变量 CURSOR_API_KEY（Dashboard → Integrations / API Keys）",
    };
  }

  const modelId = job.model?.trim() || "composer-2.5";
  const jobWithCatalog = await attachLiveCursorModelCatalog(job, apiKey);
  const selected = selectCursorSdkModelParams(jobWithCatalog);
  let params = selected.params;
  logLine(`Cursor 模型=${modelId} params=${JSON.stringify(params ?? [])}`);
  if (selected.dropped.length > 0) {
    logLine(
      `未传给 Cursor SDK：${selected.dropped.join(", ")}（当前模型目录不支持，或属于看板自造参数）。` +
        (selected.dropped.includes("fast")
          ? "当前模型没有 fast，开启快速模式不会生效。"
          : ""),
    );
  }

  const agentMcpUrl = job.round.agentEndpointUrl.trim();
  if (!agentMcpUrl) {
    return { ok: false, error: "本轮 claim 缺少 scoped MCP 端点" };
  }

  try {
    // Cursor SDK 的内置 Shell 会从 Worker 进程继承工作目录；在创建 Agent 前
    // 再次固定到目标仓库，避免 Shell 落到发布包的 agent_worker 目录。
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
      // 用户 Rule 已由 Worker 完整注入。settingSources=project 仍会扫描
      // 用户主目录，但按仓库路径过滤后再注入；不含 user，避免用户 Skill
      // 与 ~/.cursor/mcp.json 进入模型。
      settingSources: ["project"],
      store: new JsonlLocalAgentStore(storeDir),
      ...(askUserTool ? { customTools: { ask_user: askUserTool } } : {}),
      // 无头 Worker 无人点批准；Auto-review 会拦 ready_to_submit 导致整卡失败。
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
            `Cursor 拒绝参数 ${stripped.dropped.join(", ")}，已去掉后重试创建会话。`,
          );
        }
        agent = await Agent.create({
          ...createOptions(params),
          disallowedTools,
        });
      }
      logLine(
        `本地运行：JSONL 存储=${storeDir}；沙箱${job.enableSandbox === true ? "开启" : "关闭"}；` +
          `合并 MCP（${mcp.names.join(", ") || "无"}）；` +
          `kanbanMCP 强制为 scoped（${agentMcpUrl}）；` +
          `禁用工具=${disallowedTools.join(",") || "无"}；` +
          `settingSources=project（SDK 扫描用户主目录后按仓库路径过滤；用户 Rule 已由 Worker 注入；保留项目规则 / Skill / Hooks）`,
      );
      logLine("本地会话已创建，开始执行…");
      emitSessionStart(job);
      const sessionUser = sessionStartText(job);
      if (sessionUser) live.push({ role: "user", text: sessionUser });
      const emittedAssistant = new Set<string>();
      const emitAssistant = (text: string): void => {
        const normalized = text.trim();
        if (!normalized || emittedAssistant.has(normalized)) return;
        emittedAssistant.add(normalized);
        live.push({ role: "assistant", text: normalized });
        emitAssistantMessage(job, normalized);
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
      const run = await agent.send({
        text: askUserTool
          ? `${job.prompt}\n\n## 看板交互\n需要用户确认时必须调用 ask_user；不要调用 askQuestion。ask_user 会暂停本轮并等待看板回复。`
          : job.prompt,
        images: job.round.images,
      }, {
        mcpServers: mcp.servers,
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
            if (described.lines.length > 0) {
              logLines(described.lines, described.source);
            }
            if (step.type === "assistantMessage") {
              emitAssistant(extractCursorAssistantStepText(step));
            }
          } catch {
            logLine("收到一步进度");
          }
          try {
            const event = shellSpans.observe(step, Date.now());
            if (isShellSpanEvent(event)) {
              await job.round.reportShellSpan?.(event);
            }
          } catch (err) {
            logLine(
              `上报 Shell 时间线失败：${err instanceof Error ? err.message : String(err)}`,
            );
          }
        },
      });
      cancellation?.onCancel(() => {
        void run.cancel().catch(() => undefined);
      });
      if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
        await run.cancel().catch(() => undefined);
      }
      const result = await run.wait();
      let turns: unknown[] = [];
      try {
        turns = await run.conversation();
        for (const text of assistantTextsFromTurns(turns)) {
          emitAssistant(text);
        }
      } catch {
        // 会话快照不可用时仍用 result.result 兜底。
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
      logLine(
        `Cursor run id=${result.id} status=${result.status} steps=${stepCount} tools=${toolCallCount} elapsedMs=${Date.now() - startedAt}`,
      );
      if (result.usage && toDashboardTokenUsage(result.usage).totalTokens > 0) {
        logLine(formatSessionTokenLog(result.usage, metrics));
      }
      if (cancellation?.isSkipRequested) {
        logLine("Cursor 会话已由用户跳过", "worker");
        return { ok: false, error: "已跳过" };
      }
      if (cancellation?.isCancelled || result.status === "cancelled") {
        logLine("Cursor 会话已由用户停止", "worker");
        return { ok: false, error: "已取消" };
      }
      if (result.status === "error") {
        return {
          ok: false,
          error: `Cursor run 失败：${result.error?.message ?? result.id}`,
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
            ? "Cursor 会话完成"
            : `Cursor 状态：${result.status}`;

      return { ok: result.status === "finished", summary };
    } finally {
      stopScanLog();
      if (agent) await settleWithin(8000, agent[Symbol.asyncDispose]());
    }
  } catch (err) {
    if (cancellation?.isSkipRequested) {
      return { ok: false, error: "已跳过" };
    }
    if (cancellation?.isCancelled) {
      return { ok: false, error: "已取消" };
    }
    if (err instanceof CursorAgentError) {
      return {
        ok: false,
        error: `Cursor 启动失败：${err.message}（retryable=${err.isRetryable}）`,
        // SDK 偶尔会把连接中断标为不可重试，保留本地网络错误兜底。
        retryable: err.isRetryable || isRetryableError(err),
      };
    }
    return {
      ok: false,
      error: `Cursor 会话异常：${err instanceof Error ? err.message : String(err)}`,
      retryable: isRetryableError(err),
    };
  }
}
