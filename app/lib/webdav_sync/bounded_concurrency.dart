/// WebDAV 单次同步内的传输并发上限。
///
/// 取值偏保守，避免部分网盘对多连接限流或断连。
const kWebDavTransferConcurrency = 4;

/// 以不超过 [concurrency] 的并发执行 [action]。
///
/// 某项失败后不再领取新任务；已在飞的任务会跑完，再抛出遇到的第一个错误。
Future<void> runBounded<T>(
  Iterable<T> items, {
  int concurrency = kWebDavTransferConcurrency,
  required Future<void> Function(T item) action,
}) async {
  final list = items.toList(growable: false);
  if (list.isEmpty) return;

  var workers = concurrency;
  if (workers < 1) workers = 1;
  if (workers > list.length) workers = list.length;

  var next = 0;
  Object? error;
  StackTrace? stackTrace;

  Future<void> worker() async {
    while (true) {
      if (error != null) return;
      final index = next;
      next += 1;
      if (index >= list.length) return;
      try {
        await action(list[index]);
      } catch (e, st) {
        error ??= e;
        stackTrace ??= st;
      }
    }
  }

  await Future.wait(List<Future<void>>.generate(workers, (_) => worker()));
  final firstError = error;
  if (firstError != null) {
    Error.throwWithStackTrace(firstError, stackTrace ?? StackTrace.empty);
  }
}
