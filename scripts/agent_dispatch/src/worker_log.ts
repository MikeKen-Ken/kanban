import { writeSync } from "node:fs";

/** 管道 stdout 下立刻刷出一行，避免 Worker 进度被块缓冲吞掉。 */
export function workerLog(line: string): void {
  writeSync(1, `${line}\n`);
}
