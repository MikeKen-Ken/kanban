import 'dart:async';

/// 异步互斥：将临界区串行化，避免并发 `await` 交错破坏共享状态。
class AsyncMutex {
  Future<void> _tail = Future<void>.value();

  /// 等待先前临界区结束后执行 [action]；同链可重入需由调用方自行处理。
  Future<T> guard<T>(Future<T> Function() action) {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    return previous.then((_) => action()).whenComplete(() {
      if (!gate.isCompleted) {
        gate.complete();
      }
    });
  }
}
