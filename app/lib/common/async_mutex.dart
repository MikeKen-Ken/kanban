import 'dart:async';

/// 异步互斥：将临界区串行化，避免并发 `await` 交错破坏共享状态。
class AsyncMutex {
  Future<void> _tail = Future<void>.value();
  final Object _zoneKey = Object();

  /// 等待先前临界区结束后执行 [action]。
  ///
  /// 只有从当前 [action] 同步派生并等待的调用链可以重入；其他 UI、MCP
  /// 或同步任务即使在当前临界区的 `await` 期间到达，也必须排队。
  Future<T> guard<T>(Future<T> Function() action) {
    final currentLease = Zone.current[_zoneKey];
    if (currentLease is _AsyncMutexLease &&
        identical(currentLease.owner, this) &&
        currentLease.isActive) {
      return action();
    }

    final previous = _tail;
    final gate = Completer<void>();
    final lease = _AsyncMutexLease(this);
    _tail = gate.future;
    return previous
        .then((_) async {
          try {
            return await runZoned(
              action,
              zoneValues: {_zoneKey: lease},
            );
          } finally {
            // 临界区结束后，内部派生但未等待的任务不能继续冒充重入调用。
            lease.isActive = false;
          }
        })
        .whenComplete(() {
      if (!gate.isCompleted) {
        gate.complete();
      }
    });
  }
}

class _AsyncMutexLease {
  _AsyncMutexLease(this.owner);

  final AsyncMutex owner;
  bool isActive = true;
}
