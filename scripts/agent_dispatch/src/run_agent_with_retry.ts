import type { WorkerCancellation } from "./cancellation.ts";
import { isRetryableError, sleep } from "./retry.ts";
import type { DispatchResult, RoundDispatchJob } from "./types.ts";
import { workerLog } from "./worker_log.ts";

// 给短时断网留出 15 秒恢复窗口（1s + 2s + 4s + 8s），同时保持有限重试。
const MAX_AGENT_ATTEMPTS = 5;
const BASE_RETRY_DELAY_MS = 1000;

export async function runAgentWithRetry(
  runAgent: (
    job: RoundDispatchJob,
    cancellation?: WorkerCancellation,
  ) => Promise<DispatchResult>,
  job: RoundDispatchJob,
  cancellation?: WorkerCancellation,
  wait: (ms: number) => Promise<void> = sleep,
): Promise<DispatchResult> {
  for (let attempt = 1; attempt <= MAX_AGENT_ATTEMPTS; attempt += 1) {
    cancellation?.throwIfCancelled();

    try {
      const result = await runAgent(job, cancellation);
      if (
        result.ok ||
        cancellation?.isCancelled ||
        cancellation?.isSkipRequested ||
        result.error === "已取消" ||
        result.error === "已跳过" ||
        !isRetryableAgentResult(result) ||
        attempt >= MAX_AGENT_ATTEMPTS
      ) {
        return result;
      }

      await waitBeforeRetry(attempt, result.error ?? "Agent 会话失败", wait);
    } catch (error) {
      if (!isRetryableError(error) || attempt >= MAX_AGENT_ATTEMPTS) throw error;
      await waitBeforeRetry(
        attempt,
        error instanceof Error ? error.message : String(error),
        wait,
      );
    }

    if (cancellation?.isSkipRequested) {
      return { ok: false, error: "已跳过" };
    }
  }

  return { ok: false, error: "Agent 会话重试次数已耗尽" };
}

export function isRetryableAgentResult(result: DispatchResult): boolean {
  return result.retryable === true ||
    (result.retryable !== false && isRetryableError(result.error));
}

async function waitBeforeRetry(
  attempt: number,
  reason: string,
  wait: (ms: number) => Promise<void>,
): Promise<void> {
  const delayMs = BASE_RETRY_DELAY_MS * 2 ** (attempt - 1);
  workerLog(
    `Agent 会话暂时失败（第 ${attempt}/${MAX_AGENT_ATTEMPTS} 次）：${reason}；${delayMs}ms 后自动重试`,
    "worker",
    "warning",
  );
  await wait(delayMs);
}
