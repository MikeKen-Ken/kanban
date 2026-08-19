import { type WorkerLogSource, workerLog } from "./worker_log.ts";

export type CursorThinkingStreamOptions = {
  write?: (line: string, source?: WorkerLogSource) => void;
  intervalMs?: number;
  schedule?: (fn: () => void, ms: number) => { cancel: () => void };
};

function defaultSchedule(fn: () => void, ms: number): { cancel: () => void } {
  const timer = setTimeout(fn, ms);
  timer.unref?.();
  return { cancel: () => clearTimeout(timer) };
}

/** 把 Cursor SDK 的思考增量刷进 Worker 日志，避免整段思考结束后才第一次出现。 */
export class CursorThinkingStream {
  private readonly write: (line: string, source?: WorkerLogSource) => void;
  private readonly intervalMs: number;
  private readonly schedule: (fn: () => void, ms: number) => { cancel: () => void };
  private pending = "";
  private assembled = "";
  private startedBlock = false;
  private streamed = false;
  private scheduled: { cancel: () => void } | undefined;

  constructor(options: CursorThinkingStreamOptions = {}) {
    this.write = options.write ?? ((line, source) => workerLog(line, source ?? "ai"));
    this.intervalMs = options.intervalMs ?? 800;
    this.schedule = options.schedule ?? defaultSchedule;
  }

  notePromptSent(): void {
    this.write(
      "已发送任务，正在等待模型思考流。完整思考步骤要等这段思考结束后才到达，中间空白不代表空闲。",
      "worker",
    );
  }

  handleDelta(update: unknown): void {
    if (!update || typeof update !== "object") return;
    const record = update as { type?: unknown; text?: unknown; thinkingDurationMs?: unknown };
    const type = typeof record.type === "string" ? record.type : "";
    if (type === "thinking-delta" && typeof record.text === "string" && record.text) {
      this.appendDelta(record.text);
      return;
    }
    if (type === "thinking-completed") {
      this.flush(true);
      const ms = record.thinkingDurationMs;
      if (typeof ms === "number" && Number.isFinite(ms) && ms >= 0) {
        this.write(`思考完成（${Math.round(ms / 1000)} 秒）`, "ai");
      }
    }
  }

  /** 若思考已通过增量打出，则跳过 onStep 的整段重复 dump。 */
  consumeStreamedThinking(): boolean {
    if (!this.streamed) return false;
    this.streamed = false;
    this.startedBlock = false;
    this.assembled = "";
    return true;
  }

  dispose(): void {
    this.scheduled?.cancel();
    this.scheduled = undefined;
    this.flush(true);
  }

  private appendDelta(text: string): void {
    const addition = this.deltaAddition(text);
    if (!addition) return;
    this.pending += addition;
    if (this.pending.includes("\n")) {
      this.flush(false);
      return;
    }
    this.ensureScheduled();
  }

  private deltaAddition(text: string): string {
    if (this.assembled && text.startsWith(this.assembled) && text.length >= this.assembled.length) {
      const extra = text.slice(this.assembled.length);
      this.assembled = text;
      return extra;
    }
    this.assembled += text;
    return text;
  }

  private ensureScheduled(): void {
    if (this.scheduled || this.pending.length === 0) return;
    this.scheduled = this.schedule(() => {
      this.scheduled = undefined;
      this.flush(false);
    }, this.intervalMs);
  }

  private flush(force: boolean): void {
    if (!this.pending) return;
    let emit = this.pending;
    let keep = "";
    if (!force) {
      const lastNl = this.pending.lastIndexOf("\n");
      if (lastNl < 0) {
        emit = this.pending;
        keep = "";
      } else {
        emit = this.pending.slice(0, lastNl);
        keep = this.pending.slice(lastNl + 1);
      }
    }
    this.pending = keep;
    const lines = emit
      .split(/\r?\n/)
      .map((line) => line.replace(/\s+$/, ""))
      .filter((line) => line.length > 0);
    if (lines.length === 0) return;
    this.streamed = true;
    for (const line of lines) {
      if (!this.startedBlock) {
        this.write(`思考：${line}`, "ai");
        this.startedBlock = true;
      } else {
        this.write(`  │ ${line}`, "ai");
      }
    }
  }
}
