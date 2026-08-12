import { Agent, CursorAgentError } from "@cursor/sdk";
import { resolveModelParams, type DispatchJob, type DispatchResult } from "./types.js";

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
  console.log(
    `Cursor 模型=${modelId} params=${JSON.stringify(params ?? [])}`,
  );

  try {
    const result = await Agent.prompt(job.prompt, {
      apiKey,
      model: {
        id: modelId,
        ...(params ? { params } : {}),
      },
      local: {
        cwd: job.cwd,
        // 需要用户级 MCP（kanbanMCP）与项目规则
        settingSources: ["user", "project"],
      },
    });

    if (result.status === "error") {
      return {
        ok: false,
        error: `Cursor run 失败：${result.id ?? "unknown"}`,
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
