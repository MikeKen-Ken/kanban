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
  private blockComplete = false;
  private scheduled: { cancel: () => void } | undefined;

  constructor(options: CursorThinkingStreamOptions = {}) {
    this.write = options.write ?? ((line, source) => workerLog(line, source ?? "ai"));
    this.intervalMs = options.intervalMs ?? 800;
    this.schedule = options.schedule ?? defaultSchedule;
  }

  notePromptSent(): void {
    this.write(
      "Task sent; waiting for the model thinking stream. Full thinking steps arrive after this block completes; a blank gap in between does not mean idle.",
      "worker",
    );
  }

  handleDelta(update: unknown): void {
    if (!update || typeof update !== "object") return;
    const record = update as {
      type?: unknown;
      text?: unknown;
      delta?: unknown;
      thinkingDurationMs?: unknown;
      message?: unknown;
    };
    const type = typeof record.type === "string" ? record.type : "";
    const nested =
      record.message && typeof record.message === "object"
        ? (record.message as { text?: unknown })
        : undefined;
    const deltaText = [record.text, record.delta, nested?.text].find(
      (value): value is string => typeof value === "string" && value.length > 0,
    );
    if (type === "thinking" && deltaText) {
      this.replaceAssembled(deltaText);
      return;
    }
    if (type === "thinking-delta" && deltaText) {
      this.appendDelta(deltaText);
      return;
    }
    if (type === "thinking-completed") {
      this.flush(true);
      this.blockComplete = true;
      const ms = record.thinkingDurationMs;
      if (typeof ms === "number" && Number.isFinite(ms) && ms >= 0) {
        this.write(`Thinking done (${Math.round(ms / 1000)}s)`, "ai");
      }
    }
  }

  /** 当前已组装的思考正文，供写入同步对话；不消费日志去重状态。 */
  assembledText(): string {
    return `${this.assembled}${this.pending}`.trim();
  }

  /** 若思考已通过增量打出，则跳过 onStep 的整段重复 dump。 */
  consumeStreamedThinking(): boolean {
    if (!this.streamed) return false;
    this.streamed = false;
    this.startedBlock = false;
    return true;
  }

  dispose(): void {
    this.scheduled?.cancel();
    this.scheduled = undefined;
    this.flush(true);
  }

  private replaceAssembled(text: string): void {
    if (this.blockComplete) {
      this.assembled = "";
      this.pending = "";
      this.startedBlock = false;
      this.streamed = false;
      this.blockComplete = false;
    }
    this.assembled = text;
    this.pending = "";
  }

  private appendDelta(text: string): void {
    if (this.blockComplete) {
      this.assembled = "";
      this.pending = "";
      this.startedBlock = false;
      this.streamed = false;
      this.blockComplete = false;
    }
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
        this.write(`Thinking: ${line}`, "ai");
        this.startedBlock = true;
      } else {
        this.write(`  │ ${line}`, "ai");
      }
    }
  }
}
