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

/** \u628A Cursor SDK \u7684\u601D\u8003\u589E\u91CF\u5237\u8FDB Worker \u65E5\u5FD7，\u907F\u514D\u6574\u6BB5\u601D\u8003\u7ED3\u675F\u540E\u624D\u7B2C\u4E00\u6B21\u51FA\u73B0。 */
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

  /** \u5F53\u524D\u5DF2\u7EC4\u88C5\u7684\u601D\u8003\u6B63\u6587，\u4F9B\u5199\u5165\u540C\u6B65\u5BF9\u8BDD；\u4E0D\u6D88\u8D39\u65E5\u5FD7\u53BB\u91CD\u72B6\u6001。 */
  assembledText(): string {
    return `${this.assembled}${this.pending}`.trim();
  }

  /** \u82E5\u601D\u8003\u5DF2\u901A\u8FC7\u589E\u91CF\u6253\u51FA，\u5219\u8DF3\u8FC7 onStep \u7684\u6574\u6BB5\u91CD\u590D dump。 */
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
