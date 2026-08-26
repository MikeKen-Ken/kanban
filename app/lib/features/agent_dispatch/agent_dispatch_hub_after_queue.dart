import 'agent_dispatch_after_queue.dart';

/// 总览完成后队列跟踪的单个批次结果。
enum AgentDispatchHubBatchOutcome { success, failure, cancelled }

/// 一次总览调度波次：从总览启动的项目，以及它们结束后要推送的仓库。
class AgentDispatchHubAfterQueueWave {
  final _repoByProject = <String, String>{};
  final _outcomes = <String, AgentDispatchHubBatchOutcome>{};

  bool get hasTracked => _repoByProject.isNotEmpty;

  bool get allTrackedFinished =>
      hasTracked && _repoByProject.keys.every(_outcomes.containsKey);

  Iterable<String> get projectIds => _repoByProject.keys;

  int get successCount => _count(AgentDispatchHubBatchOutcome.success);

  int get failureCount => _count(AgentDispatchHubBatchOutcome.failure);

  int get cancelledCount => _count(AgentDispatchHubBatchOutcome.cancelled);

  /// 按首次跟踪顺序去重后的仓库路径。
  List<String> get uniqueRepoPaths {
    final seen = <String>{};
    final repos = <String>[];
    for (final repo in _repoByProject.values) {
      if (repo.isEmpty || !seen.add(repo)) continue;
      repos.add(repo);
    }
    return repos;
  }

  void track({required String projectId, required String repoPath}) {
    final id = projectId.trim();
    if (id.isEmpty) return;
    _repoByProject[id] = repoPath.trim();
  }

  void recordOutcome({
    required String projectId,
    required AgentDispatchHubBatchOutcome outcome,
  }) {
    final id = projectId.trim();
    if (!_repoByProject.containsKey(id)) return;
    _outcomes[id] = outcome;
  }

  void clear() {
    _repoByProject.clear();
    _outcomes.clear();
  }

  int _count(AgentDispatchHubBatchOutcome outcome) =>
      _outcomes.values.where((item) => item == outcome).length;
}

/// 总览完成后队列运行态：跟踪波次，并在全部批次结束后触发执行。
class AgentDispatchHubAfterQueueController {
  final wave = AgentDispatchHubAfterQueueWave();

  Future<void> Function()? _runner;
  Future<void>? _inFlight;
  void Function()? onChanged;
  var _running = false;

  bool get pending => wave.hasTracked;

  bool get running => _running;

  set running(bool value) {
    if (_running == value) return;
    _running = value;
    onChanged?.call();
  }

  void bindRunner(Future<void> Function() runner) {
    _runner = runner;
  }

  void trackHubStart({
    required String projectId,
    required String repoPath,
  }) {
    wave.track(projectId: projectId, repoPath: repoPath);
    onChanged?.call();
  }

  void recordOutcome({
    required String projectId,
    required AgentDispatchHubBatchOutcome outcome,
  }) {
    wave.recordOutcome(projectId: projectId, outcome: outcome);
    onChanged?.call();
  }

  Future<void> tryRun() async {
    final runner = _runner;
    if (runner == null) return;
    _inFlight ??= runner().whenComplete(() {
      _inFlight = null;
    });
    await _inFlight;
  }

  void reset() {
    wave.clear();
    _runner = null;
    _inFlight = null;
    _running = false;
    onChanged?.call();
  }
}

/// 由 Worker 结果解析总览波次结果。
AgentDispatchHubBatchOutcome hubAfterQueueOutcome({
  required bool ok,
  String? error,
}) {
  if (ok) return AgentDispatchHubBatchOutcome.success;
  final text = (error ?? '').trim().toLowerCase();
  if (text == 'canceled' || text == 'cancelled' || error == '已取消') {
    return AgentDispatchHubBatchOutcome.cancelled;
  }
  return AgentDispatchHubBatchOutcome.failure;
}

bool isAgentDispatchMachineAfterStep(AgentDispatchAfterStep step) =>
    step == AgentDispatchAfterStep.hibernate ||
    step == AgentDispatchAfterStep.shutdown;

/// 总览队列含休眠/关机时，项目队列先去掉同一步骤，避免其它批次还在跑时关机。
List<AgentDispatchAfterStep> applyHubAfterQueueDeferral(
  List<AgentDispatchAfterStep> projectSteps, {
  required bool hubWavePending,
  required List<AgentDispatchAfterStep> hubSteps,
}) {
  if (!hubWavePending) {
    return List<AgentDispatchAfterStep>.unmodifiable(projectSteps);
  }
  final defer = {
    for (final step in hubSteps)
      if (isAgentDispatchMachineAfterStep(step)) step,
  };
  if (defer.isEmpty) {
    return List<AgentDispatchAfterStep>.unmodifiable(projectSteps);
  }
  return List<AgentDispatchAfterStep>.unmodifiable([
    for (final step in projectSteps)
      if (!defer.contains(step)) step,
  ]);
}

/// 全部正在跑的调度批次结束后，是否执行总览完成后队列。
bool shouldRunHubAfterQueue({
  required bool anyDispatchRunning,
  required bool allTrackedFinished,
  required int successCount,
  required int failureCount,
  required int cancelledCount,
  required bool runOnFailure,
  required bool queueNonEmpty,
}) {
  if (!queueNonEmpty) return false;
  if (anyDispatchRunning) return false;
  if (!allTrackedFinished) return false;
  if (successCount == 0 && failureCount == 0) return false;
  if (failureCount == 0) return true;
  return runOnFailure;
}

/// 因又有批次启动而推迟休眠/关机。
class HubAfterQueueDeferred implements Exception {
  const HubAfterQueueDeferred(this.message);

  final String message;

  @override
  String toString() => message;
}
