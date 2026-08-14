import { WorkerCancelledError, type WorkerCancellation } from "./cancellation.js";
import { KanbanMcpClient } from "./mcp_client.js";
import { runCodex } from "./run_codex.js";
import { runCursor } from "./run_cursor.js";
import type { DispatchJob, DispatchResult } from "./types.js";
import { workerLog } from "./worker_log.js";

function cardState(card: Record<string, unknown>): "verify" | "blocked" | "active" {
  const columnId = String(card.columnId ?? "");
  const columnName = String(card.columnName ?? "");
  if (columnId === "verify" || columnName === "待验证") return "verify";
  if (columnId === "blocked" || columnName === "阻塞中") return "blocked";
  return "active";
}

export async function runBatch(
  job: DispatchJob,
  cancellation?: WorkerCancellation,
): Promise<DispatchResult> {
  const mcp = new KanbanMcpClient();
  const limit = Math.max(1, Math.min(999, Math.trunc(job.cardLimit)));
  let processedCards = 0;
  workerLog(`Worker 批次启动：endpoint=${job.mcpEndpoint} limit=${limit}`);

  const cancelledResult = (): DispatchResult => ({
    ok: false,
    error: "已取消",
    processedCards,
  });

  const drainedResult = (): DispatchResult => ({
    ok: true,
    summary: `已在当前会话结束后停止；已处理 ${processedCards} 张`,
    processedCards,
  });

  try {
    await mcp.connect(job.mcpEndpoint);
    workerLog("Worker 已连接看板 MCP；Worker 只读检查队列，Skill 自己领取卡片");

    for (let index = 1; index <= limit; index += 1) {
      if (cancellation?.shouldStopAfterCurrentSession) {
        return cancellation.isCancelled ? cancelledResult() : drainedResult();
      }
      workerLog(`──────── Worker 单卡轮次 ${index}/${limit} ────────`);
      const peek = await mcp.callJson("peek_next_card", {
        ...(job.projectId ? { projectId: job.projectId } : {}),
      });

      if (peek.found !== true) {
        workerLog(`[success] Worker 检查结果：无更多卡片；已处理 ${processedCards} 张`);
        return {
          ok: true,
          summary: `Worker 批次完成：已处理 ${processedCards} 张，当前无更多卡片`,
          processedCards,
        };
      }

      await mcp.callJson("dispatch_begin_agent_session", {
        workerToken: job.workerToken,
      });
      workerLog("Worker 检查结果：还有卡片；正在创建全新的 Skill 会话");
      const result =
        job.engine === "codex"
          ? await runCodex(job, cancellation)
          : await runCursor(job, cancellation);
      if (cancellation?.isCancelled) {
        return cancelledResult();
      }
      if (!result.ok) {
        if (result.error === "已取消") return cancelledResult();
        return {
          ok: false,
          error: result.error ?? `第 ${index} 次 Skill 会话失败`,
          processedCards,
        };
      }

      workerLog("Worker 已确认 Agent 会话结束，正在读取本轮卡片状态");
      const session = await mcp.callJson("dispatch_agent_session_status", {
        workerToken: job.workerToken,
      });
      const cardId = String(session.cardId ?? "").trim();
      const projectId = String(session.projectId ?? job.projectId ?? "").trim();
      const deniedPickCount = Number(session.deniedPickCount ?? 0);
      if (deniedPickCount > 0) {
        return {
          ok: false,
          error: `第 ${index} 次 Skill 会话重复调用了 pick_next_card，Worker 停止批次`,
          processedCards,
        };
      }
      if (session.pickClaimed !== true || !cardId) {
        return {
          ok: false,
          error: `第 ${index} 次 Skill 会话没有成功领取一张卡片，Worker 停止批次`,
          processedCards,
        };
      }

      let latest: Record<string, unknown>;
      try {
        latest = await mcp.callJson("get_card", {
          cardId,
          ...(projectId ? { projectId } : {}),
        });
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        workerLog(
          `[warn] Worker 无法读取本轮卡片状态（${message}）；可能卡片已被删除，跳过本轮并继续下一张`,
        );
        continue;
      }
      const state = cardState(latest);
      workerLog(
        `Worker 状态检查：cardId=${cardId} column=${String(latest.columnName ?? latest.columnId ?? "未知")}`,
      );
      if (state === "blocked") {
        return {
          ok: false,
          error: `卡片 ${cardId} 已进入阻塞中，Worker 停止批次`,
          processedCards,
        };
      }
      if (state !== "verify") {
        return {
          ok: false,
          error: `卡片 ${cardId} 未进入待验证，Worker 判定本轮未完成并停止批次`,
          processedCards,
        };
      }

      processedCards += 1;
      workerLog(`[success] Worker 确认第 ${index} 次 Skill 只处理一张且已送验；会话已释放`);
      if (cancellation?.shouldStopAfterCurrentSession) {
        return cancellation.isCancelled ? cancelledResult() : drainedResult();
      }
    }

    workerLog(`[success] Worker 批次完成：已达到上限并处理 ${processedCards} 张`);
    return {
      ok: true,
      summary: `Worker 批次完成：已达到上限并处理 ${processedCards} 张`,
      processedCards,
    };
  } catch (err) {
    if (err instanceof WorkerCancelledError) {
      return cancelledResult();
    }
    throw err;
  } finally {
    workerLog("Worker 正在关闭看板 MCP 连接…");
    await mcp.close().catch(() => undefined);
    workerLog("Worker 已关闭看板 MCP 连接");
  }
}
