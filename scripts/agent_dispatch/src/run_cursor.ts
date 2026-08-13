import { writeSync } from "node:fs";
import { Agent, CursorAgentError } from "@cursor/sdk";
import { settleWithin } from "./async_limit.js";
import { resolveModelParams, type DispatchJob, type DispatchResult } from "./types.js";

function logLine(line: string): void {
  writeSync(1, `${line}\n`);
}

function clip(text: string, max = 240): string {
  const compact = text.replace(/\s+/g, " ").trim();
  if (compact.length <= max) return compact;
  return `${compact.slice(0, max)}…`;
}

function describeStep(step: { type?: unknown; message?: unknown }): string {
  const type = String(step.type ?? "unknown");
  const message =
    step.message && typeof step.message === "object"
      ? (step.message as Record<string, unknown>)
      : undefined;
  switch (type) {
    case "assistantMessage":
      return `助手：${clip(String(message?.text ?? ""))}`;
    case "thinkingMessage":
      return "思考中…";
    case "toolCall":
      return `工具：${String(message?.type ?? "tool")}`;
    case "shellConversationTurn":
    case "shell":
      return `命令：${clip(String(message?.command ?? message?.text ?? ""))}`;
    default:
      return `步骤：${type}`;
  }
}

export async function runCursor(job: DispatchJob): Promise<DispatchResult> {
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
    const agent = await Agent.create({
      apiKey,
      model: {
        id: modelId,
        ...(params ? { params } : {}),
      },
      local: {
        cwd: job.cwd,
        settingSources: ["user", "project"],
      },
    });
    try {
      logLine("本地会话已创建，开始执行…");
      const run = await agent.send(job.prompt, {
        onStep: ({ step }) => {
          try {
            stepCount += 1;
            if (step.type === "toolCall") toolCallCount += 1;
            logLine(describeStep(step as { type?: unknown; message?: unknown }));
          } catch {
            logLine("收到一步进度");
          }
        },
      });
      const result = await run.wait();
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
