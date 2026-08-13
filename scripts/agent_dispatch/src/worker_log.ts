import { writeSync } from "node:fs";

export type WorkerLogSource = "worker" | "ai" | "mcp" | "shell";

/** 管道 stdout 下立刻刷出一行，避免 Worker 进度被块缓冲吞掉。 */
export function workerLog(line: string, source: WorkerLogSource = "worker"): void {
  writeSync(1, `[${source}] ${line}\n`);
}
