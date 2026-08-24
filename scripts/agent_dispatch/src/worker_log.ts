import { writeSync } from "node:fs";

export type WorkerLogSource = "worker" | "ai" | "mcp" | "shell";

export type WorkerLogLevel = "info" | "success" | "warning" | "error";

export type WorkerLogRecord = {
  line: string;
  source?: WorkerLogSource;
  level?: WorkerLogLevel;
};

/** \u7BA1\u9053 stdout \u4E0B\u7ACB\u523B\u5237\u51FA\u4E00\u884C，\u907F\u514D Worker \u8FDB\u5EA6\u88AB\u5757\u7F13\u51B2\u541E\u6389。 */
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
