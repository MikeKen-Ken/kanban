import '../../controllers/board_controller.dart';
import '../mcp/mcp_block_card.dart';
import '../mcp/mcp_pick_next_card.dart';
import '../mcp/mcp_submit_for_verify.dart';
import 'agent_dispatch_config.dart';
import 'agent_dispatch_mcp_parse.dart';
import 'agent_dispatch_prompt.dart';
import 'agent_dispatch_worker.dart';

/// 调度一轮或多轮：取卡 → worker → 提交/阻塞。
class AgentDispatchService {
  AgentDispatchService(this.controller);

  final BoardController controller;

  bool _cancelRequested = false;

  void requestCancel() => _cancelRequested = true;

  Future<AgentDispatchBatchResult> runBatch({
    required AgentDispatchRunOptions options,
    required String? workerScriptPath,
    void Function(String line)? onLog,
  }) async {
    _cancelRequested = false;
    final repo = options.repoPath?.trim();
    if (repo == null || repo.isEmpty) {
      return const AgentDispatchBatchResult(
        processed: 0,
        succeeded: 0,
        failed: 0,
        stoppedReason: '请先勾选并填写代码仓库路径',
      );
    }

    var processed = 0;
    var succeeded = 0;
    var failed = 0;
    String? stoppedReason;

    final maxCards = options.maxCards.clamp(1, 50);
    for (var i = 0; i < maxCards; i++) {
      if (_cancelRequested) {
        stoppedReason = '已取消';
        break;
      }

      onLog?.call('—— 第 ${i + 1}/$maxCards 张 ——');
      final pick = await mcpPickNextCard(
        controller,
        projectId: options.projectId,
        includeWorkItems: true,
      );
      if (pick.isError == true) {
        failed++;
        processed++;
        final err = mcpCallToolText(pick) ?? '取卡失败';
        onLog?.call(err);
        stoppedReason = err;
        break;
      }
      final payload = mcpCallToolJson(pick);
      if (payload == null || payload['found'] != true) {
        stoppedReason = payload?['reason'] as String? ?? '没有可实施卡片';
        onLog?.call(stoppedReason);
        break;
      }

      final projectId = payload['projectId'] as String? ?? options.projectId ?? '';
      final cardId = payload['cardId'] as String? ?? '';
      final card = controller.findCardById(cardId);
      final title = card?.title ?? cardId;
      onLog?.call('取到卡片：$title ($cardId)');

      final workScope = <String, dynamic>{
        if (payload['workMode'] != null) 'workMode': payload['workMode'],
        if (payload['workItems'] != null) 'workItems': payload['workItems'],
        if (payload['labels'] != null) 'labels': payload['labels'],
      };
      final prompt = buildAgentDispatchPrompt(
        projectId: projectId,
        cardId: cardId,
        cardTitle: title,
        cardDescription: card?.description,
        workScope: workScope,
        repoPath: repo,
      );

      final workerResult = await runAgentWorkerJob(
        engine: options.engine,
        cwd: repo,
        prompt: prompt,
        model: options.model,
        effort: options.effort,
        workerScriptPath: workerScriptPath,
        onLog: onLog,
      );
      processed++;

      if (_cancelRequested) {
        stoppedReason = '已取消';
        if (options.autoBlockOnFail) {
          await mcpBlockCard(
            controller,
            cardId: cardId,
            projectId: projectId,
            reason: '调度已取消',
          );
        }
        break;
      }

      if (workerResult.ok) {
        succeeded++;
        onLog?.call(workerResult.summary ?? '实施成功');
        if (options.autoSubmitVerify) {
          final submit = await mcpSubmitCardForVerify(
            controller,
            cardId: cardId,
            projectId: projectId,
            completeAllIncompleteChecklist: true,
          );
          if (submit.isError == true) {
            onLog?.call(
              '提交待验证失败：${mcpCallToolText(submit) ?? '未知错误'}',
            );
          } else {
            onLog?.call('已移入待验证');
          }
        }
      } else {
        failed++;
        final reason = workerResult.error ?? 'worker 失败';
        onLog?.call(reason);
        if (options.autoBlockOnFail) {
          await mcpBlockCard(
            controller,
            cardId: cardId,
            projectId: projectId,
            reason: reason,
          );
          onLog?.call('已移入阻塞中');
        }
      }
    }

    return AgentDispatchBatchResult(
      processed: processed,
      succeeded: succeeded,
      failed: failed,
      stoppedReason: stoppedReason,
    );
  }
}

class AgentDispatchBatchResult {
  const AgentDispatchBatchResult({
    required this.processed,
    required this.succeeded,
    required this.failed,
    this.stoppedReason,
  });

  final int processed;
  final int succeeded;
  final int failed;
  final String? stoppedReason;
}
