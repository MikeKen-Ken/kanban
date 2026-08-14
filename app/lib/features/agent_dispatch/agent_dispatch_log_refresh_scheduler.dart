import 'dart:async';

/// 合并调度日志的界面刷新，避免 Worker 高频输出时逐行重建工作台。
class AgentDispatchLogRefreshScheduler {
  AgentDispatchLogRefreshScheduler({
    this.interval = const Duration(milliseconds: 100),
  });

  final Duration interval;
  Timer? _timer;

  void schedule(void Function() refresh) {
    _timer ??= Timer(interval, () {
      _timer = null;
      refresh();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
