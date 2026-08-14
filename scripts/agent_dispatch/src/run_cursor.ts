import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { Agent, CursorAgentError, JsonlLocalAgentStore } from "@cursor/sdk";
import { settleWithin } from "./async_limit.js";
import type { WorkerCancellation } from "./cancellation.js";
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

function pickString(message: Record<string, unknown> | undefined, ...keys: string[]): string {
  if (!message) return "";
  for (const key of keys) {
    const value = message[key];
    if (typeof value === "string" && value.trim()) return value;
  }
  return "";
}

function describeStep(step: { type?: unknown; message?: unknown }): {
  lines: string[];
  source: WorkerLogSource;
} {
  const type = String(step.type ?? "unknown");
  const message =
    step.message && typeof step.message === "object"
      ? (step.message as Record<string, unknown>)
      : undefined;
  switch (type) {
    case "assistantMessage":
      return {
        lines: expandMultiline("助手：", String(message?.text ?? "")),
        source: "ai",
      };
    case "thinkingMessage": {
      const text = pickString(message, "text", "thinking", "content");
      return {
        lines: text ? expandMultiline("思考：", text) : ["思考中…"],
        source: "ai",
      };
    }
    case "toolCall": {
      const toolName = pickString(
        message,
        "name",
        "toolName",
        "functionName",
        "type",
      ) || "tool";
      const args = message?.args ?? message?.arguments ?? message?.input;
      const lines = [`工具：${toolName}`];
      if (args !== undefined) {
        lines.push(`  参数：${formatJson(args)}`);
      }
      return { lines, source: "mcp" };
    }
    case "toolResult": {
      const toolName = pickString(message, "name", "toolName", "type") || "tool";
      const result = message?.result ?? message?.output ?? message?.content ?? message?.text;
      const lines = [`工具结果：${toolName}`];
      if (result !== undefined) {
        const body = typeof result === "string" ? result : formatJson(result);
        lines.push(...expandMultiline("  返回：", body));
      }
      return { lines, source: "mcp" };
    }
    case "shellConversationTurn":
    case "shell": {
      const command = pickString(message, "command", "text");
      return {
        lines: expandMultiline("命令：", command),
        source: "shell",
      };
    }
    default: {
      const detail = message ? formatJson(message, 800) : "";
      return {
        lines: detail ? [`步骤：${type} ${detail}`] : [`步骤：${type}`],
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

  try {
    const startedAt = Date.now();
    let stepCount = 0;
    let toolCallCount = 0;
    const storeDir = join(homedir(), ".cursor", "kanban-agent-jsonl-store");
    mkdirSync(storeDir, { recursive: true });
    logLine(
      `本地运行：JSONL 存储=${storeDir}；沙箱关闭；网络传输使用 SDK 默认配置；` +
        `仅注入看板 MCP（${job.mcpEndpoint}），不加载用户级 MCP`,
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
          url: job.mcpEndpoint,
        },
      },
      local: {
        cwd: job.cwd,
        settingSources: ["project"],
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
            logLines(described.lines, described.source);
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
        logLine(
          `本会话 token：input=${result.usage.inputTokens} output=${result.usage.outputTokens} total=${result.usage.totalTokens}`,
        );
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
