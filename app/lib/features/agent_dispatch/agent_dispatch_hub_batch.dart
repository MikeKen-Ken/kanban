import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/board_controller.dart';
import '../kanban/next_work_card.dart';
import 'agent_dispatch_after_queue.dart';
import 'agent_dispatch_config.dart';
import 'agent_dispatch_hub_after_queue.dart';
import 'agent_dispatch_log.dart';
import 'agent_dispatch_model_catalog_store.dart';
import 'agent_dispatch_registry.dart';
import 'agent_dispatch_settings.dart';

/// 总览启动批次的校验/取消结果；成功启动后由后台继续跑完。
enum AgentDispatchHubBatchStartStatus {
  started,
  alreadyRunning,
  validationFailed,
  cancelled,
}

class AgentDispatchHubBatchStartResult {
  const AgentDispatchHubBatchStartResult._({
    required this.status,
    this.message,
  });

  const AgentDispatchHubBatchStartResult.started()
      : this._(status: AgentDispatchHubBatchStartStatus.started);

  const AgentDispatchHubBatchStartResult.alreadyRunning()
      : this._(
          status: AgentDispatchHubBatchStartStatus.alreadyRunning,
          message: 'This project is already running',
        );

  const AgentDispatchHubBatchStartResult.validationFailed(String message)
      : this._(
          status: AgentDispatchHubBatchStartStatus.validationFailed,
          message: message,
        );

  const AgentDispatchHubBatchStartResult.cancelled()
      : this._(status: AgentDispatchHubBatchStartStatus.cancelled);

  final AgentDispatchHubBatchStartStatus status;
  final String? message;

  bool get ok => status == AgentDispatchHubBatchStartStatus.started;
}

/// 用本机已保存的调度设置，从总览直接启动项目批次（不必先打开工作台）。
Future<AgentDispatchHubBatchStartResult> startAgentDispatchFromHub({
  required String projectId,
  required BoardController board,
  required Future<bool> Function(String otherProjectId, String repo)
      confirmSameRepo,
}) async {
  final id = projectId.trim();
  if (id.isEmpty) {
    return const AgentDispatchHubBatchStartResult.validationFailed(
        'Invalid project');
  }

  final service = AgentDispatchRegistry.instance.forProject(id);
  if (service.isRunning) {
    return const AgentDispatchHubBatchStartResult.alreadyRunning();
  }

  final prefs = await SharedPreferences.getInstance();
  final loaded = prefs.loadAgentDispatchSettings();
  final repo = (loaded.repoPathFor(id) ?? '').trim();
  final projectMissing = board.manifest?.findById(id) == null;
  final countInvalid = !loaded.cardLimitMax &&
      (loaded.cardLimitCount < 1 || loaded.cardLimitCount > 999);

  if (projectMissing) {
    return const AgentDispatchHubBatchStartResult.validationFailed(
        'Project not found');
  }
  if (countInvalid) {
    return const AgentDispatchHubBatchStartResult.validationFailed(
      'Invalid card limit; adjust it to 1–999 in the workspace',
    );
  }
  if (!board.mcpHost.isRunning) {
    return const AgentDispatchHubBatchStartResult.validationFailed(
      'Kanban MCP is not running; enable MCP in Settings first',
    );
  }

  final conflict = AgentDispatchRegistry.instance.runningWithRepo(
    repo,
    exceptProjectId: id,
  );
  if (conflict != null) {
    final confirmed = await confirmSameRepo(conflict.projectId, repo);
    if (!confirmed) {
      return const AgentDispatchHubBatchStartResult.cancelled();
    }
    if (service.isRunning) {
      return const AgentDispatchHubBatchStartResult.alreadyRunning();
    }
  }

  final next = loaded
      .viewForProject(id)
      .copyWith(
        useProject: true,
        projectId: id,
      )
      .bindRepoToProject(id, repo);
  // 只更新仓库绑定与最近项目；引擎/模型按项目隔离，不回写全局种子。
  await prefs.saveAgentDispatchSettings(
    loaded.copyWith(
      useProject: true,
      projectId: id,
      repoPathByProject: next.repoPathByProject,
      repoPaths: next.repoPaths,
    ),
  );

  final catalogs = {
    for (final engine in AgentDispatchEngine.values)
      engine: prefs.loadAgentDispatchModelCatalog(engine: engine),
  };
  final options = next.toRunOptions(
    projectTitleOf: (pid) => board.manifest?.findById(pid)?.title,
    catalogs: catalogs,
  );

  var queueSize = 0;
  await board.runOnProject(id, () async {
    final current = board.board;
    if (current != null) queueSize = countWorkQueueCards(current);
  });

  await service.hydrateLog();
  service.appendLog(
    '\n—— ${DateTime.now().toLocal().toString().substring(0, 19)} New run ——',
  );
  service.appendLog('Engine: ${options.engine.label}');
  service.appendLog('Started from overview');

  final registry = AgentDispatchRegistry.instance;
  final hubQueue = registry.hubAfterQueue;
  hubQueue.trackHubStart(projectId: id, repoPath: repo);
  hubQueue.bindRunner(() => executeAgentDispatchHubAfterQueue(board: board));

  unawaited(
    service
        .runOnce(
      options: options,
      boardController: board,
      skillPath: next.resolveSkillPath(),
      mcpEndpoint: board.mcpHost.endpointUrl,
      closeScopedEndpoint: board.mcpHost.closeScopedEndpoint,
      workerScriptPath: next.workerScriptPath,
      queueSize: queueSize,
      afterQueue: applyHubAfterQueueDeferral(
        next.afterQueueFor(id),
        hubWavePending: true,
        hubSteps: next.hubAfterQueue,
      ),
      runAfterQueueOnFailure: next.runAfterQueueOnFailureFor(id),
      resolveAfterQueue: () async {
        final latestPrefs = await SharedPreferences.getInstance();
        final latest = latestPrefs.loadAgentDispatchSettings();
        return (
          steps: applyHubAfterQueueDeferral(
            latest.afterQueueFor(id),
            hubWavePending: hubQueue.pending,
            hubSteps: latest.hubAfterQueue,
          ),
          runOnFailure: latest.runAfterQueueOnFailureFor(id),
        );
      },
      afterQueueHost: AgentDispatchAfterQueueHost(
        uploadAll: board.uploadNow,
        gitPush: () => gitPushWithRebase(repoPath: options.repoPath),
        hibernate: windowsHibernateNow,
        shutdown: windowsShutdownNow,
      ),
    )
        .then((result) {
      if (result.ok) {
        service.appendLog(
          result.summary ?? 'Complete',
          level: AgentDispatchLogLevel.success,
        );
      } else if (result.error == 'Canceled') {
        service.appendLog('Run stopped', level: AgentDispatchLogLevel.warning);
      }
      hubQueue.recordOutcome(
        projectId: id,
        outcome: hubAfterQueueOutcome(ok: result.ok, error: result.error),
      );
      return hubQueue.tryRun();
    }),
  );

  return const AgentDispatchHubBatchStartResult.started();
}

/// 所有正在跑的批次结束后，按最新总览完成后队列执行一次。
Future<void> executeAgentDispatchHubAfterQueue({
  BoardController? board,
  AgentDispatchRegistry? registry,
  Future<AgentDispatchAfterQueueSnapshot> Function()? resolveQueue,
  bool Function()? anyDispatchRunning,
  AgentDispatchAfterQueueHost Function(List<String> repos)? hostForRepos,
}) async {
  final dispatch = registry ?? AgentDispatchRegistry.instance;
  final hubQueue = dispatch.hubAfterQueue;
  bool runningNow() => anyDispatchRunning?.call() ?? dispatch.anyRunning;

  if (hubQueue.running) return;
  if (runningNow() || !hubQueue.wave.allTrackedFinished) return;

  AgentDispatchAfterQueueSnapshot snapshot;
  if (resolveQueue != null) {
    snapshot = await resolveQueue();
  } else {
    final prefs = await SharedPreferences.getInstance();
    final latest = prefs.loadAgentDispatchSettings();
    snapshot = (
      steps: latest.hubAfterQueue,
      runOnFailure: latest.hubRunAfterQueueOnFailure,
    );
  }

  final shouldRun = shouldRunHubAfterQueue(
    anyDispatchRunning: runningNow(),
    allTrackedFinished: hubQueue.wave.allTrackedFinished,
    successCount: hubQueue.wave.successCount,
    failureCount: hubQueue.wave.failureCount,
    cancelledCount: hubQueue.wave.cancelledCount,
    runOnFailure: snapshot.runOnFailure,
    queueNonEmpty: snapshot.steps.isNotEmpty,
  );
  if (!shouldRun) {
    if (runningNow() || !hubQueue.wave.allTrackedFinished) return;
    hubQueue.reset();
    return;
  }

  if (runningNow()) return;

  final projectIds = hubQueue.wave.projectIds.toList();
  final repos = hubQueue.wave.uniqueRepoPaths;
  void log(String message,
      {AgentDispatchLogLevel level = AgentDispatchLogLevel.info}) {
    for (final projectId in projectIds) {
      dispatch.forProject(projectId).appendLog(message, level: level);
    }
  }

  hubQueue.running = true;
  var keepWave = false;
  try {
    if (runningNow()) {
      keepWave = true;
      return;
    }
    if (hubQueue.wave.failureCount > 0) {
      log(
        'Overview completion queue: a batch failed; continuing because "run after failure" is enabled',
        level: AgentDispatchLogLevel.warning,
      );
    }
    final host = hostForRepos?.call(repos) ??
        AgentDispatchAfterQueueHost(
          uploadAll: board!.uploadNow,
          gitPush: () => _pushHubRepos(repos, log),
          hibernate: () => _hubPowerAction(
            runningNow: runningNow,
            action: windowsHibernateNow,
            label: 'Hibernate',
          ),
          shutdown: () => _hubPowerAction(
            runningNow: runningNow,
            action: windowsShutdownNow,
            label: 'Shut down',
          ),
        );
    await runAgentDispatchAfterQueue(
      steps: snapshot.steps,
      host: host,
      onLog: log,
    );
  } on HubAfterQueueDeferred catch (error) {
    log('$error', level: AgentDispatchLogLevel.warning);
    keepWave = true;
  } catch (error) {
    log(
      'Overview completion queue interrupted: $error',
      level: AgentDispatchLogLevel.error,
    );
  } finally {
    hubQueue.running = false;
    final stillActive =
        keepWave || runningNow() || !hubQueue.wave.allTrackedFinished;
    if (!stillActive) hubQueue.reset();
  }
}

Future<void> _pushHubRepos(
  List<String> repos,
  void Function(String message, {AgentDispatchLogLevel level}) log,
) async {
  if (repos.isEmpty) {
    log('Completion queue: no repositories to push');
    return;
  }
  for (final repo in repos) {
    log('Completion queue: pushing $repo');
    await gitPushWithRebase(repoPath: repo);
  }
}

Future<void> _hubPowerAction({
  required bool Function() runningNow,
  required Future<void> Function() action,
  required String label,
}) async {
  if (runningNow()) {
    throw HubAfterQueueDeferred(
      'Overview completion queue: skipped $label because a dispatch batch is still running',
    );
  }
  await action();
}

/// 从总览立即停止指定项目的批次。
Future<void> stopAgentDispatchFromHub(String projectId) {
  return AgentDispatchRegistry.instance
      .forProject(projectId.trim())
      .requestCancel();
}
