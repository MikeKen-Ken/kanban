import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { Agent, CursorAgentError, JsonlLocalAgentStore } from "@cursor/sdk";
import { settleWithin } from "./async_limit.js";
import type { WorkerCancellation } from "./cancellation.js";
import { formatSessionTokenLog } from "./cursor_token_usage.js";
import { resolveModelParams, type DispatchJob, type DispatchResult } from "./types.js";
import { type WorkerLogSource, workerLog } from "./worker_log.js";

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
  const trimmed = body.trimEnd();
  if (!trimmed) return [`${prefix}（空）`];
  const lines = trimmed.split(/\r?\n/);
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
} {
  const record = asRecord(step) ?? {};
  const type = String(record.type ?? "unknown");
  const message = toolPayload(record);
  switch (type) {
    case "assistantMessage":
      return {
        lines: expandMultiline("助手：", String(message?.text ?? "")),
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
        return { lines: [], source: isShellTool(toolName) ? "shell" : "mcp" };
      }
      if (isShellTool(toolName)) {
        return { lines: expandMultiline("命令：", detail), source: "shell" };
      }
      return {
        lines: expandMultiline(`工具：${toolName} `, detail),
        source: "mcp",
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

export async function runCursor(
  job: DispatchJob,
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
  const params = resolveModelParams(job);
  logLine(`Cursor 模型=${modelId} params=${JSON.stringify(params ?? [])}`);

  const agentMcpUrl = job.agentMcpEndpoint?.trim();
  if (!agentMcpUrl) {
    return { ok: false, error: "缺少 Skill 会话 MCP 端点 agentMcpEndpoint" };
  }

  try {
    // Cursor SDK 的内置 Shell 会从 Worker 进程继承工作目录；在创建 Agent 前
    // 再次固定到目标仓库，避免 Shell 落到发布包的 agent_worker 目录。
    process.chdir(job.cwd);
    const startedAt = Date.now();
    let stepCount = 0;
    let toolCallCount = 0;
    const storeDir = join(homedir(), ".cursor", "kanban-agent-jsonl-store");
    mkdirSync(storeDir, { recursive: true });
    logLine(
      `本地运行：JSONL 存储=${storeDir}；沙箱关闭；` +
        `仅注入看板精简 MCP（${agentMcpUrl}），不加载用户级 MCP；` +
        `settingSources 为空（不注入项目规则与个人 Skill）`,
    );
    const agent = await Agent.create({
      apiKey,
      model: {
        id: modelId,
        ...(params ? { params } : {}),
      },
      mcpServers: {
        kanbanMCP: {
          type: "http",
          url: agentMcpUrl,
        },
      },
      local: {
        cwd: job.cwd,
        // 流程已由注入的 Skill 正文给出。加载 project 会把仓库规则与个人 Skill
        // 整包塞进会话（日志里常见 skillCount=21、ruleCount=32），cacheRead 可达上百万。
        settingSources: [],
        store: new JsonlLocalAgentStore(storeDir),
        sandboxOptions: { enabled: false },
      },
    });
    try {
      logLine("本地会话已创建，开始执行…");
      const run = await agent.send(job.prompt, {
        onStep: ({ step }) => {
          try {
            stepCount += 1;
            if (step.type === "toolCall") toolCallCount += 1;
            const described = describeStep(
              step as { type?: unknown; message?: unknown },
            );
            if (described.lines.length > 0) {
              logLines(described.lines, described.source);
            }
          } catch {
            logLine("收到一步进度");
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
      if (cancellation?.isSkipRequested) {
        logLine("Cursor 会话已由用户跳过", "worker");
        return { ok: false, error: "已跳过" };
      }
      if (cancellation?.isCancelled || result.status === "cancelled") {
        logLine("Cursor 会话已由用户停止", "worker");
        return { ok: false, error: "已取消" };
      }
      logLine(
        `Cursor run id=${result.id} status=${result.status} steps=${stepCount} tools=${toolCallCount} elapsedMs=${Date.now() - startedAt}`,
      );
      if (result.usage) {
        logLine(formatSessionTokenLog(result.usage));
      }

      if (result.status === "error") {
        return {
          ok: false,
          error: `Cursor run 失败：${result.error?.message ?? result.id}`,
          summary: typeof result.result === "string" ? result.result : undefined,
        };
      }

      const summary =
        typeof result.result === "string"
          ? result.result
          : result.status === "finished"
            ? "Cursor 会话完成"
            : `Cursor 状态：${result.status}`;

      return { ok: result.status === "finished", summary };
    } finally {
      await settleWithin(8000, agent[Symbol.asyncDispose]());
    }
  } catch (err) {
    if (err instanceof CursorAgentError) {
      return {
        ok: false,
        error: `Cursor 启动失败：${err.message}（retryable=${err.isRetryable}）`,
      };
    }
    throw err;
  }
}
