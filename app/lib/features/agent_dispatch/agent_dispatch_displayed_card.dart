import 'agent_dispatch_log.dart';
import 'agent_dispatch_progress.dart';

/// 日志状态区当前应展示的卡片：选中任务优先，否则跟正在跑的那张。
class AgentDispatchDisplayedCard {
  const AgentDispatchDisplayedCard({
    required this.progress,
    required this.running,
    required this.logSlice,
    required this.canJumpToRunning,
    this.runningOrdinal,
  });

  final AgentDispatchProgress progress;
  final bool running;
  final String logSlice;
  final bool canJumpToRunning;
  final int? runningOrdinal;

  static AgentDispatchDisplayedCard resolve({
    required String fullLog,
    required List<AgentDispatchLogTask> tasks,
    required int? selectedOrdinal,
    required AgentDispatchProgress live,
    required bool batchRunning,
  }) {
    final runningOrdinal = runningTaskOrdinal(tasks, live, batchRunning);
    if (tasks.isEmpty) {
      return AgentDispatchDisplayedCard(
        progress: live,
        running: batchRunning,
        logSlice: '',
        canJumpToRunning: false,
        runningOrdinal: null,
      );
    }

    final viewingHistorical = selectedOrdinal != null &&
        (runningOrdinal == null || selectedOrdinal != runningOrdinal);
    final canJump = batchRunning &&
        runningOrdinal != null &&
        selectedOrdinal != runningOrdinal;

    if (!viewingHistorical) {
      final sliceOrdinal = selectedOrdinal ??
          runningOrdinal ??
          (tasks.isNotEmpty ? tasks.last.ordinal : null);
      return AgentDispatchDisplayedCard(
        progress: live,
        running: batchRunning,
        logSlice: AgentDispatchLogTasks.slice(fullLog, sliceOrdinal),
        canJumpToRunning: canJump,
        runningOrdinal: runningOrdinal,
      );
    }

    final task =
        tasks.where((item) => item.ordinal == selectedOrdinal).firstOrNull;
    if (task == null) {
      return AgentDispatchDisplayedCard(
        progress: live,
        running: batchRunning,
        logSlice: fullLog,
        canJumpToRunning: canJump,
        runningOrdinal: runningOrdinal,
      );
    }

    final slice = AgentDispatchLogTasks.slice(fullLog, task.ordinal);
    return AgentDispatchDisplayedCard(
      progress: reconstruct(task, slice),
      running: false,
      logSlice: slice,
      canJumpToRunning: canJump,
      runningOrdinal: runningOrdinal,
    );
  }

  /// 正在跑的那张在日志任务列表中的序号；批次未运行则为 null。
  static int? runningTaskOrdinal(
    List<AgentDispatchLogTask> tasks,
    AgentDispatchProgress live,
    bool batchRunning,
  ) {
    if (!batchRunning || tasks.isEmpty) return null;
    if (live.currentRound > 0) {
      final byRound =
          tasks.where((task) => task.roundIndex == live.currentRound);
      if (byRound.isNotEmpty) return byRound.last.ordinal;
      final byOrdinal =
          tasks.where((task) => task.ordinal == live.currentRound);
      if (byOrdinal.isNotEmpty) return byOrdinal.last.ordinal;
    }
    return tasks.last.ordinal;
  }

  static AgentDispatchProgress reconstruct(
    AgentDispatchLogTask task,
    String slice,
  ) {
    var progress = AgentDispatchProgress(
      currentRound: task.roundIndex,
      totalCards: task.roundTotal,
      processedCards: task.roundIndex,
    );
    for (final line in slice.split('\n')) {
      if (line.trim().isEmpty) continue;
      progress = applyWorkerProgressLog(
        progress,
        AgentDispatchLogEntry.messageOf(line),
      );
    }
    final title = progress.currentTitle.trim().isEmpty
        ? task.title
        : progress.currentTitle;
    return progress.copyWith(
      running: false,
      processedCards: task.roundIndex,
      totalCards: task.roundTotal > 0 ? task.roundTotal : progress.totalCards,
      currentTitle: title,
      phaseLabel: _historicalPhase(progress.phaseLabel),
    );
  }

  static String _historicalPhase(String phase) {
    const inProgress = {'', 'Claim', 'Implement', 'Retry', 'Submit'};
    if (inProgress.contains(phase.trim())) return 'Completed';
    return phase.trim();
  }
}
