import 'package:mcp_dart/mcp_dart.dart';

import '../../../common/git_commit_ref.dart';
import '../../../controllers/board_controller.dart';
import '../../activity/activity_models.dart';
import '../mcp_git_commit.dart';
import '../mcp_dispatch_card_gate.dart';
import '../mcp_submission_snapshot_store.dart';
import '../mcp_submit_for_verify.dart';
import '../mcp_tool_results.dart';
import 'dispatch_pending_store.dart';

Future<CallToolResult> dispatchFinalize(
  BoardController controller, {
  required String workerToken,
  required String sessionId,
  DispatchPendingStore? pendingStore,
  McpSubmissionSnapshotStore? snapshotStore,
  McpGitRunner? gitRunner,
}) async {
  final store = pendingStore ?? DispatchPendingStore();
  var record = await store.read(sessionId);
  if (record == null ||
      !McpDispatchCardGate.instance.authorizesPending(
        workerToken: workerToken,
        projectId: record.projectId,
        repoPath: record.repoPath,
      )) {
    return mcpErrorResult('未找到该 Worker 的 pending 会话');
  }
  if (record.status == DispatchPendingStatus.finalized) {
    return _finalizedResult(record);
  }
  if (record.status == DispatchPendingStatus.failed) {
    return mcpErrorResult(record.error ?? 'pending 会话已失败');
  }
  if (record.status == DispatchPendingStatus.declared) {
    return mcpErrorResult('尚未记录验证结果');
  }

  await refreshMcpGitAuthorIdentity();

  final repo = record.repoPath?.trim();
  if (repo != null && repo.isNotEmpty) {
    if (record.status == DispatchPendingStatus.committing) {
      final recovered = await findMcpCommitByDispatchTrailers(
        repoPath: repo,
        sessionId: record.sessionId,
        cardId: record.cardId,
        runner: gitRunner,
      );
      if (recovered != null) {
        record = record.copyWith(
          status: DispatchPendingStatus.committed,
          commitRef: abbreviateGitCommitRef(recovered),
          clearError: true,
        );
        await store.write(record);
      }
    }

    if (record.status == DispatchPendingStatus.validated ||
        record.status == DispatchPendingStatus.committing) {
      final head = await mcpGitHeadHash(repo, runner: gitRunner);
      final baseline = record.baselineCommitRef;
      if (baseline != null && head != baseline) {
        final failed = record.copyWith(
          status: DispatchPendingStatus.failed,
          error: '检测到 Agent 自行移动 HEAD：baseline=$baseline，HEAD=$head',
        );
        await store.write(failed);
        return mcpErrorResult(failed.error!);
      }

      var tree = await inspectMcpGitTree(repo, runner: gitRunner);
      final revertCommit = record.gitRevertCommit;
      if (revertCommit != null) {
        if (tree.kind != McpGitTreeKind.clean) {
          final failed = record.copyWith(
            status: DispatchPendingStatus.failed,
            error: '受控 Git revert 要求领取后的工作区保持干净',
          );
          await store.write(failed);
          return mcpErrorResult(failed.error!);
        }
        final reverted = await revertMcpCommitWithoutCommit(
          repoPath: repo,
          commitRef: revertCommit,
          runner: gitRunner,
        );
        if (!reverted.ok) {
          final failed = record.copyWith(
            status: DispatchPendingStatus.failed,
            error: reverted.error ?? 'git revert 失败',
          );
          await store.write(failed);
          return mcpErrorResult(failed.error!);
        }
        tree = await inspectMcpGitTree(repo, runner: gitRunner);
      }
      if (tree.kind == McpGitTreeKind.dirty) {
        final nested = await findMcpSingleDirtySubmodule(
          repo,
          runner: gitRunner,
        );
        if (nested != null) {
          final nestedChanged =
              await listMcpGitChangedPaths(nested.repoPath, runner: gitRunner);
          if (nestedChanged == null) {
            return mcpErrorResult('无法读取嵌套 Git 仓库的变更清单');
          }
          final nestedSensitive =
              nestedChanged.where(isMcpSensitiveGitPath).toList();
          if (nestedSensitive.isNotEmpty) {
            final failed = record.copyWith(
              status: DispatchPendingStatus.failed,
              error: '嵌套 Git 仓库包含敏感文件，拒绝提交：${nestedSensitive.join(', ')}',
            );
            await store.write(failed);
            return mcpErrorResult(failed.error!);
          }
          final snapshot = await (snapshotStore ?? McpSubmissionSnapshotStore())
              .read(projectId: record.projectId, cardId: record.cardId);
          if (snapshot == null) return mcpErrorResult('提交范围快照已丢失');
          record = record.copyWith(
            status: DispatchPendingStatus.committing,
            clearError: true,
          );
          await store.write(record);
          final nestedCommit = await commitMcpWorkingTree(
            repoPath: nested.repoPath,
            message: snapshot.suggestedCommitMessage,
            trailers: [
              'Kanban-Session: ${record.sessionId}',
              'Kanban-Card: ${record.cardId}',
            ],
            runner: gitRunner,
          );
          if (!nestedCommit.ok) {
            final failed = record.copyWith(
              status: DispatchPendingStatus.failed,
              error: nestedCommit.error ?? '嵌套 Git 仓库提交失败',
            );
            await store.write(failed);
            return mcpErrorResult(failed.error!);
          }
          final parentChanged =
              await listMcpGitChangedPaths(repo, runner: gitRunner);
          if (parentChanged == null ||
              parentChanged.length != 1 ||
              parentChanged.single != nested.parentRelativePath) {
            final failed = record.copyWith(
              status: DispatchPendingStatus.failed,
              error: '嵌套仓库已提交，但父仓库还有其它改动；已停止以避免混合提交',
            );
            await store.write(failed);
            return mcpErrorResult(failed.error!);
          }
          tree = await inspectMcpGitTree(repo, runner: gitRunner);
        }
        final changed = await listMcpGitChangedPaths(repo, runner: gitRunner);
        if (changed == null) return mcpErrorResult('无法读取 Git 变更清单');
        final sensitive = changed.where(isMcpSensitiveGitPath).toList();
        if (sensitive.isNotEmpty) {
          if (revertCommit != null) {
            await abortMcpGitRevert(repoPath: repo, runner: gitRunner);
          }
          final failed = record.copyWith(
            status: DispatchPendingStatus.failed,
            error: '检测到敏感文件，拒绝提交：${sensitive.join(', ')}',
          );
          await store.write(failed);
          return mcpErrorResult(failed.error!);
        }
        final snapshot =
            await (snapshotStore ?? McpSubmissionSnapshotStore()).read(
          projectId: record.projectId,
          cardId: record.cardId,
        );
        if (snapshot == null) return mcpErrorResult('提交范围快照已丢失');
        record = record.copyWith(
          status: DispatchPendingStatus.committing,
          clearError: true,
        );
        await store.write(record);
        final committed = await commitMcpWorkingTree(
          repoPath: repo,
          message: revertCommit == null
              ? snapshot.suggestedCommitMessage
              : 'Revert $revertCommit',
          trailers: [
            'Kanban-Session: ${record.sessionId}',
            'Kanban-Card: ${record.cardId}',
          ],
          runner: gitRunner,
        );
        if (!committed.ok) {
          final failed = record.copyWith(
            status: DispatchPendingStatus.failed,
            error: committed.error ?? 'Git 提交失败',
          );
          await store.write(failed);
          return mcpErrorResult(failed.error!);
        }
        record = record.copyWith(
          status: DispatchPendingStatus.committed,
          commitRef: abbreviateGitCommitRef(committed.commitRef!),
          clearError: true,
        );
        await store.write(record);
      } else if (tree.kind == McpGitTreeKind.clean) {
        record = record.copyWith(
          status: DispatchPendingStatus.committed,
          commitRef: head == null ? null : abbreviateGitCommitRef(head),
          clearError: true,
        );
        await store.write(record);
      } else {
        record = record.copyWith(
          status: DispatchPendingStatus.committed,
          clearError: true,
        );
        await store.write(record);
      }
    }

    if (record.status == DispatchPendingStatus.committed) {
      final afterCommit = await inspectMcpGitTree(repo, runner: gitRunner);
      if (afterCommit.kind == McpGitTreeKind.dirty) {
        const error = 'Git 提交后工作区不干净，拒绝更新看板。请清理工作区后重新运行批次以恢复送验。';
        record = record.copyWith(error: error);
        await store.write(record);
        return mcpJsonResult({
          'ok': false,
          'sessionId': record.sessionId,
          'projectId': record.projectId,
          'cardId': record.cardId,
          'status': record.status.name,
          if (record.commitRef != null) 'commitRef': record.commitRef,
          'error': error,
          'preservePending': true,
        });
      }
    }
  } else if (record.status == DispatchPendingStatus.validated) {
    record = record.copyWith(
      status: DispatchPendingStatus.committed,
      clearError: true,
    );
    await store.write(record);
  }

  if (record.status != DispatchPendingStatus.committed) {
    return mcpErrorResult('pending 状态无法 finalize：${record.status.name}');
  }
  final submitted = await mcpSubmitCardForVerify(
    controller,
    cardId: record.cardId,
    projectId: record.projectId,
    completedChecklistIds: record.completedChecklistIds,
    completedFeedbackIds: record.completedFeedbackIds,
    completeAllIncompleteFeedback: false,
    commitRef: record.commitRef,
  );
  if (submitted.isError == true) return submitted;

  final projectId = record.projectId;
  final cardId = record.cardId;
  final cardTitle = await controller.runOnProject(
    projectId,
    () async => controller.findCardById(cardId)?.title ?? cardId,
  );
  await controller.recordActivity(
    projectId: record.projectId,
    entityId: record.cardId,
    entityTitle: cardTitle,
    action: ActivityAction.updated,
    source: ActivitySource.mcp,
    details: _validationActivityDetails(record),
  );

  record = record.copyWith(
    status: DispatchPendingStatus.finalized,
    clearError: true,
  );
  await store.write(record);
  return _finalizedResult(record);
}

CallToolResult _finalizedResult(DispatchPendingRecord record) => mcpJsonResult({
      'ok': true,
      'sessionId': record.sessionId,
      'projectId': record.projectId,
      'cardId': record.cardId,
      'status': record.status.name,
      if (record.commitRef != null) 'commitRef': record.commitRef,
    });

Map<String, String> _validationActivityDetails(
  DispatchPendingRecord record,
) {
  final manual = record.manualVerificationReason?.trim();
  final totalDurationMs = record.validationResults.fold<int>(
    0,
    (total, result) => total + result.durationMs,
  );
  return {
    'validationMode': manual == null ? 'session' : 'manual',
    'commandCount': '${record.verificationCommands.length}',
    'totalDurationMs': '$totalDurationMs',
    if (manual != null) 'manualReason': _truncateActivityValue(manual),
    'resultSummary': _truncateActivityValue(
      manual == null ? '会话内验证' : '人工验证：待人工验收',
    ),
  };
}

String _truncateActivityValue(String value) =>
    value.length <= 500 ? value : '${value.substring(0, 499)}…';
