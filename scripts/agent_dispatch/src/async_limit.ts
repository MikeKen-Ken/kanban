/** \u7B49\u5F85 [work] \u7ED3\u675F；\u8D85\u65F6\u540E\u4E0D\u518D\u963B\u585E\u8C03\u7528\u65B9（\u540E\u53F0 Promise \u4ECD\u53EF\u80FD\u5360\u7528\u4E8B\u4EF6\u5FAA\u73AF）。 */
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
