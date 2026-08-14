import { existsSync } from "node:fs";

export class WorkerCancelledError extends Error {
  constructor(message = "已取消") {
    super(message);
    this.name = "WorkerCancelledError";
  }
}

type CancelCallback = () => void | Promise<void>;

/** Worker 批次取消：SIGTERM/SIGINT、cancelFile 轮询与活动会话回调。 */
export class WorkerCancellation {
  private cancelled = false;
  private drainAfterCurrent = false;
  private skipRequested = false;
  private reason = "已取消";
  private readonly callbacks = new Set<CancelCallback>();
  private cancelFileTimer: NodeJS.Timeout | undefined;
  private drainFileTimer: NodeJS.Timeout | undefined;
  private skipFileTimer: NodeJS.Timeout | undefined;
  private signalInstalled = false;

  watchCancelFile(path: string): void {
    const check = (): void => {
      if (this.cancelled) return;
      try {
        if (existsSync(path)) this.cancel("已取消");
      } catch {
        // ignore
      }
    };
    check();
    this.cancelFileTimer = setInterval(check, 200);
    this.cancelFileTimer.unref?.();
  }

  watchDrainFile(path: string): void {
    const check = (): void => {
      if (this.drainAfterCurrent || this.cancelled) return;
      try {
        if (existsSync(path)) this.requestDrainAfterCurrent();
      } catch {
        // ignore
      }
    };
    check();
    this.drainFileTimer = setInterval(check, 200);
    this.drainFileTimer.unref?.();
  }

  watchSkipFile(path: string): void {
    const check = (): void => {
      if (this.skipRequested || this.cancelled) return;
      try {
        if (existsSync(path)) this.requestSkipCurrentSession();
      } catch {
        // ignore
      }
    };
    check();
    this.skipFileTimer = setInterval(check, 200);
    this.skipFileTimer.unref?.();
  }

  installSignalHandlers(): void {
    if (this.signalInstalled) return;
    this.signalInstalled = true;
    const onSignal = (): void => {
      this.cancel("已取消");
    };
    process.once("SIGTERM", onSignal);
    process.once("SIGINT", onSignal);
  }

  get isCancelled(): boolean {
    return this.cancelled;
  }

  get isSkipRequested(): boolean {
    return this.skipRequested;
  }

  get shouldStopAfterCurrentSession(): boolean {
    return this.cancelled || this.drainAfterCurrent;
  }

  requestDrainAfterCurrent(): void {
    if (this.cancelled || this.drainAfterCurrent) return;
    this.drainAfterCurrent = true;
  }

  /** 跳过当前 Skill 会话并继续批次下一张；不标记整批取消。 */
  requestSkipCurrentSession(): void {
    if (this.cancelled || this.skipRequested) return;
    this.skipRequested = true;
    for (const callback of this.callbacks) {
      void this.invoke(callback);
    }
  }

  clearSkipRequest(): void {
    this.skipRequested = false;
  }

  onCancel(callback: CancelCallback): void {
    this.callbacks.add(callback);
    if (this.cancelled) void this.invoke(callback);
  }

  cancel(reason = "已取消"): void {
    if (this.cancelled) return;
    this.cancelled = true;
    this.reason = reason;
    for (const callback of this.callbacks) {
      void this.invoke(callback);
    }
  }

  throwIfCancelled(): void {
    if (this.cancelled) throw new WorkerCancelledError(this.reason);
  }

  dispose(): void {
    if (this.cancelFileTimer) {
      clearInterval(this.cancelFileTimer);
      this.cancelFileTimer = undefined;
    }
    if (this.drainFileTimer) {
      clearInterval(this.drainFileTimer);
      this.drainFileTimer = undefined;
    }
    if (this.skipFileTimer) {
      clearInterval(this.skipFileTimer);
      this.skipFileTimer = undefined;
    }
  }

  private async invoke(callback: CancelCallback): Promise<void> {
    try {
      await callback();
    } catch {
      // ignore
    }
  }
}
