import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/board_controller.dart';
import '../kanban/next_work_card.dart';
import 'agent_dispatch_after_queue.dart';
import 'agent_dispatch_config.dart';
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
      afterQueue: next.afterQueueFor(id),
      runAfterQueueOnFailure: next.runAfterQueueOnFailureFor(id),
      resolveAfterQueue: () async {
        final latestPrefs = await SharedPreferences.getInstance();
        final latest = latestPrefs.loadAgentDispatchSettings();
        return (
          steps: latest.afterQueueFor(id),
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
    }),
  );

  return const AgentDispatchHubBatchStartResult.started();
}

/// 从总览立即停止指定项目的批次。
Future<void> stopAgentDispatchFromHub(String projectId) {
  return AgentDispatchRegistry.instance
      .forProject(projectId.trim())
      .requestCancel();
}
