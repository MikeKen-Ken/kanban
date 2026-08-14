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

function clip(text: string, max = 240): string {
  const compact = text.replace(/\s+/g, " ").trim();
  if (compact.length <= max) return compact;
  return `${compact.slice(0, max)}…`;
}

function describeStep(step: { type?: unknown; message?: unknown }): {
  text: string;
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
        text: `助手：${clip(String(message?.text ?? ""))}`,
        source: "ai",
      };
    case "thinkingMessage":
      return { text: "思考中…", source: "ai" };
    case "toolCall":
      return {
        text: `工具：${String(message?.type ?? "tool")}`,
        source: "mcp",
      };
    case "shellConversationTurn":
    case "shell":
      return {
        text: `命令：${clip(String(message?.command ?? message?.text ?? ""))}`,
        source: "shell",
      };
    default:
      return { text: `步骤：${type}`, source: "worker" };
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
            logLine(described.text, described.source);
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
