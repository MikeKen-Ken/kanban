/** 等待 [work] 结束；超时后不再阻塞调用方（后台 Promise 仍可能占用事件循环）。 */
export function settleWithin(ms: number, work: Promise<unknown>): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    timer.unref?.();
    work.then(
      () => {
        clearTimeout(timer);
        resolve();
      },
      () => {
        clearTimeout(timer);
        resolve();
      },
    );
  });
}
