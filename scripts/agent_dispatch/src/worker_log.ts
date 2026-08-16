import { writeSync } from "node:fs";

export type WorkerLogSource = "worker" | "ai" | "mcp" | "shell";

export type WorkerLogLevel = "info" | "success" | "warning" | "error";

export type WorkerLogRecord = {
  line: string;
  source?: WorkerLogSource;
  level?: WorkerLogLevel;
};

/** 管道 stdout 下立刻刷出一行，避免 Worker 进度被块缓冲吞掉。 */
export function workerLog(
  line: string,
  source: WorkerLogSource = "worker",
  level: WorkerLogLevel = "info",
): void {
  const prefix =
    level === "info" ? `[${source}]` : `[${level}] [${source}]`;
  for (const part of line.split(/\r?\n/)) {
    writeSync(1, `${prefix} ${part}\n`);
  }
}

export function workerLogRecords(records: readonly WorkerLogRecord[]): void {
  for (const record of records) {
    workerLog(record.line, record.source ?? "worker", record.level ?? "info");
  }
}
