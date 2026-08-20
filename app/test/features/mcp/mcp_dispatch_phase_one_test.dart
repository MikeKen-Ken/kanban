import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/kanban/verify_column.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_claim_next_card.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_finalizer.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_full_mcp_guard.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_pending_store.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_recovery.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_ready_to_submit.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_session_end.dart';
import 'package:kanban/features/mcp/mcp_dispatch_card_gate.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _jsonOf(CallToolResult result) {
  final text = result.content.whereType<TextContent>().first.text;
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<void> _git(String repo, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: repo,
    environment: {
      ...Platform.environment,
      'GIT_AUTHOR_NAME': 'Test',
      'GIT_AUTHOR_EMAIL': 'test@example.com',
      'GIT_COMMITTER_NAME': 'Test',
      'GIT_COMMITTER_EMAIL': 'test@example.com',
    },
  );
  if (result.exitCode != 0) {
    fail('git ${args.join(' ')} 失败：${result.stdout}\n${result.stderr}');
  }
}

Future<String> _createGitRepo(Directory root, String name) async {
  final repo = Directory(p.join(root.path, name));
  await repo.create();
  await _git(repo.path, ['init']);
  await File(p.join(repo.path, 'app.txt')).writeAsString('initial\n');
  await _git(repo.path, ['add', '-A']);
  await _git(repo.path, ['commit', '-m', 'initial']);
  return repo.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;
  final gate = McpDispatchCardGate.instance;

  setUp(() async {
    gate.debugReset();
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('kanban_dispatch_v2_');
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
  });

  tearDown(() async {
    gate.debugReset();
    controller.dispose();
    // 给 _init 末尾未等待的 reminder 快照读取让出事件循环，避免删目录时误伤下一轮 setUp。
    await Future<void>.delayed(Duration.zero);
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } on FileSystemException {
      // Git 仓库删除可能仍被占用，忽略测试收尾失败。
    }
  });

  test('claim 绑定 worker 项目并返回实际卡片覆盖与 endpoint', () async {
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '模型覆盖卡'))!;
    await controller.updateCardFull(
      todo.id,
      cardId,
      agentEngine: 'cursor',
      agentModelId: 'composer-2.5',
      agentAllowDirtyWorkspace: true,
      agentEnableSandbox: true,
      agentRequireTests: false,
      agentModelParamValues: const {'fast': 'true'},
    );
    final projectId = controller.activeProjectId!;
    gate.beginBatch('worker-a', projectId: projectId);

    final result = await dispatchClaimNextCard(
      controller,
      workerToken: 'worker-a',
      startScopedEndpoint: ({
        required workerToken,
        required cardId,
      }) async =>
          'http://127.0.0.1:19000/mcp',
    );

    expect(result.isError, isNot(true));
    final payload = _jsonOf(result);
    expect(payload['projectId'], projectId);
    expect(payload['cardId'], cardId);
    expect(payload['agentModelId'], 'composer-2.5');
    expect(payload['agentModelParamValues'], {'fast': 'true'});
    expect(payload['agentAllowDirtyWorkspace'], isTrue);
    expect(payload['agentEnableSandbox'], isTrue);
    expect(payload['agentRequireTests'], isFalse);
    expect(payload['agentEndpointUrl'], 'http://127.0.0.1:19000/mcp');
    expect(payload['sessionId'], isNotEmpty);
  });

  test('claim 空队列不创建 endpoint', () async {
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
    );
    var endpointStarts = 0;
    final result = await dispatchClaimNextCard(
      controller,
      workerToken: 'worker-a',
      startScopedEndpoint: ({
        required workerToken,
        required cardId,
      }) async {
        endpointStarts++;
        return 'unused';
      },
    );

    expect(_jsonOf(result)['found'], isFalse);
    expect(endpointStarts, 0);
  });

  test('expectedCardId 漂移时拒绝且不移卡', () async {
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '漂移卡'))!;
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
    );

    final result = await dispatchClaimNextCard(
      controller,
      workerToken: 'worker-a',
      expectedCardId: 'other-card',
    );

    expect(result.isError, isTrue);
    expect(
      controller.board!.columns
          .firstWhere((item) => item.id == 'todo')
          .cards
          .any((item) => item.id == cardId),
      isTrue,
    );
  });

  test('scoped endpoint 启动失败时回滚领卡移列', () async {
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '端点失败卡'))!;
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
    );

    final result = await dispatchClaimNextCard(
      controller,
      workerToken: 'worker-a',
      startScopedEndpoint: ({
        required workerToken,
        required cardId,
      }) async {
        throw StateError('端口不可用');
      },
    );

    expect(result.isError, isTrue);
    expect(
      controller.board!.columns
          .firstWhere((item) => item.id == 'todo')
          .cards
          .any((item) => item.id == cardId),
      isTrue,
    );
  });

  test('ready 校验冻结 id 并完成 pending roundtrip', () async {
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '声明卡'))!;
    await controller.updateCardFull(
      todo.id,
      cardId,
      checklist: [
        ChecklistItem(id: 'check-a', text: 'A'),
        ChecklistItem(id: 'check-done', text: '已完成', completed: true),
      ],
      verificationFeedback: [
        ChecklistItem(id: 'feedback-a', text: '修复反馈'),
      ],
    );
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
    );
    await dispatchClaimNextCard(controller, workerToken: 'worker-a');

    final rejected = await dispatchReadyToSubmit(
      controller,
      workerToken: 'worker-a',
      cardId: cardId,
      completedChecklistIds: const ['check-done'],
      completedFeedbackIds: const [],
      verificationCommands: const [],
      manualVerificationReason: '需要人工检查视觉结果',
    );
    expect(rejected.isError, isTrue);

    final commandsRejected = await dispatchReadyToSubmit(
      controller,
      workerToken: 'worker-a',
      cardId: cardId,
      completedChecklistIds: const ['check-a'],
      completedFeedbackIds: const ['feedback-a'],
      verificationCommands: const [
        DispatchVerificationCommand(
          executable: 'flutter',
          args: ['test', 'targeted.dart'],
        ),
      ],
    );
    expect(commandsRejected.isError, isTrue);
    expect(
      commandsRejected.content.whereType<TextContent>().first.text,
      contains('验证已下放给 Agent'),
    );

    final ready = await dispatchReadyToSubmit(
      controller,
      workerToken: 'worker-a',
      cardId: cardId,
      completedChecklistIds: const ['check-a'],
      completedFeedbackIds: const ['feedback-a'],
      verificationCommands: const [],
    );
    expect(ready.isError, isNot(true));
    final sessionId = _jsonOf(ready)['sessionId'] as String;
    final persisted = await DispatchPendingStore().read(sessionId);
    expect(persisted?.status, DispatchPendingStatus.declared);
    expect(persisted?.completedChecklistIds, ['check-a']);
    expect(persisted?.completedFeedbackIds, ['feedback-a']);
    expect(persisted?.verificationCommands, isEmpty);
  });

  test('committed 恢复 finalize 只勾显式 id 且重复调用幂等', () async {
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '显式完成卡'))!;
    await controller.updateCardFull(
      todo.id,
      cardId,
      checklist: [
        ChecklistItem(id: 'check-a', text: 'A'),
        ChecklistItem(id: 'check-b', text: 'B'),
      ],
    );
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
    );
    await dispatchClaimNextCard(controller, workerToken: 'worker-a');
    final ready = await dispatchReadyToSubmit(
      controller,
      workerToken: 'worker-a',
      cardId: cardId,
      completedChecklistIds: const ['check-a'],
      completedFeedbackIds: const [],
      verificationCommands: const [],
      manualVerificationReason: '本卡无需自动命令',
    );
    final sessionId = _jsonOf(ready)['sessionId'] as String;
    final store = DispatchPendingStore();
    final declared = (await store.read(sessionId))!;
    await store
        .write(declared.copyWith(status: DispatchPendingStatus.committed));

    final first = await dispatchFinalize(
      controller,
      workerToken: 'worker-a',
      sessionId: sessionId,
    );
    final second = await dispatchFinalize(
      controller,
      workerToken: 'worker-a',
      sessionId: sessionId,
    );

    expect(
      first.isError,
      isNot(true),
      reason: first.content
          .whereType<TextContent>()
          .map((item) => item.text)
          .join(),
    );
    expect(_jsonOf(second)['status'], 'finalized');
    final card = findVerifyColumn(controller.board!.columns)!
        .cards
        .firstWhere((item) => item.id == cardId);
    expect(card.checklist.firstWhere((item) => item.id == 'check-a').completed,
        isTrue);
    expect(card.checklist.firstWhere((item) => item.id == 'check-b').completed,
        isFalse);
  });

  test('finalize 检测敏感文件后直接拒绝', () async {
    final repo = await _createGitRepo(tempDir, 'sensitive_repo');
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '敏感文件卡'))!;
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
      repoPath: repo,
    );
    await dispatchClaimNextCard(controller, workerToken: 'worker-a');
    final ready = await dispatchReadyToSubmit(
      controller,
      workerToken: 'worker-a',
      cardId: cardId,
      completedChecklistIds: const [],
      completedFeedbackIds: const [],
      verificationCommands: const [],
      manualVerificationReason: '无需自动命令',
    );
    final sessionId = _jsonOf(ready)['sessionId'] as String;
    final store = DispatchPendingStore();
    final declared = (await store.read(sessionId))!;
    await store
        .write(declared.copyWith(status: DispatchPendingStatus.validated));
    await File(p.join(repo, '.env')).writeAsString('TOKEN=secret\n');

    final result = await dispatchFinalize(
      controller,
      workerToken: 'worker-a',
      sessionId: sessionId,
    );

    expect(result.isError, isTrue);
    expect(
      result.content.whereType<TextContent>().first.text,
      contains('敏感文件'),
    );
    expect(
      (await store.read(sessionId))?.status,
      DispatchPendingStatus.failed,
    );
  });

  test('committed 后工作区仍脏则拒绝送验并保留 committed', () async {
    final repo = await _createGitRepo(tempDir, 'dirty_after_commit');
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '提交后脏工作区卡'))!;
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
      repoPath: repo,
    );
    await dispatchClaimNextCard(controller, workerToken: 'worker-a');
    final ready = await dispatchReadyToSubmit(
      controller,
      workerToken: 'worker-a',
      cardId: cardId,
      completedChecklistIds: const [],
      completedFeedbackIds: const [],
      verificationCommands: const [],
      manualVerificationReason: '无需自动命令',
    );
    final sessionId = _jsonOf(ready)['sessionId'] as String;
    final store = DispatchPendingStore();
    final declared = (await store.read(sessionId))!;
    await store.write(
      declared.copyWith(
        status: DispatchPendingStatus.committed,
        commitRef: 'abc1234',
      ),
    );
    await File(p.join(repo, 'leftover.txt')).writeAsString('仍脏\n');

    final result = await dispatchFinalize(
      controller,
      workerToken: 'worker-a',
      sessionId: sessionId,
    );

    expect(result.isError, isNot(true));
    final payload = _jsonOf(result);
    expect(payload['ok'], isFalse);
    expect(payload['preservePending'], isTrue);
    expect(payload['status'], 'committed');
    expect(payload['commitRef'], 'abc1234');
    expect(payload['error'], contains('工作区不干净'));
    final persisted = await store.read(sessionId);
    expect(persisted?.status, DispatchPendingStatus.committed);
    expect(persisted?.error, contains('工作区不干净'));
    expect(
      findVerifyColumn(controller.board!.columns)
          ?.cards
          .any((item) => item.id == cardId),
      isNot(true),
    );
  });

  test('finalize 拒绝 Agent 自行提交导致的 HEAD 漂移', () async {
    final repo = await _createGitRepo(tempDir, 'head_drift_repo');
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, 'HEAD 漂移卡'))!;
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
      repoPath: repo,
    );
    await dispatchClaimNextCard(controller, workerToken: 'worker-a');
    final ready = await dispatchReadyToSubmit(
      controller,
      workerToken: 'worker-a',
      cardId: cardId,
      completedChecklistIds: const [],
      completedFeedbackIds: const [],
      verificationCommands: const [],
      manualVerificationReason: '无需自动命令',
    );
    final sessionId = _jsonOf(ready)['sessionId'] as String;
    final store = DispatchPendingStore();
    final declared = (await store.read(sessionId))!;
    await store
        .write(declared.copyWith(status: DispatchPendingStatus.validated));
    await File(p.join(repo, 'app.txt')).writeAsString('agent commit\n');
    await _git(repo, ['add', '-A']);
    await _git(repo, ['commit', '-m', 'agent self commit']);

    final result = await dispatchFinalize(
      controller,
      workerToken: 'worker-a',
      sessionId: sessionId,
    );

    expect(result.isError, isTrue);
    expect(
      result.content.whereType<TextContent>().first.text,
      contains('自行移动 HEAD'),
    );
  });

  test('Worker 按声明受控撤销指定提交并统一收尾', () async {
    final repo = await _createGitRepo(tempDir, 'revert_repo');
    await File(p.join(repo, 'app.txt')).writeAsString('需要撤销\n');
    await _git(repo, ['add', '-A']);
    await _git(repo, ['commit', '-m', '需要撤销的变更']);
    final target = (await Process.run(
      'git',
      ['rev-parse', 'HEAD'],
      workingDirectory: repo,
    ))
        .stdout
        .toString()
        .trim();
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '撤销指定提交'))!;
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
      repoPath: repo,
    );
    await dispatchClaimNextCard(controller, workerToken: 'worker-a');
    final ready = await dispatchReadyToSubmit(
      controller,
      workerToken: 'worker-a',
      cardId: cardId,
      completedChecklistIds: const [],
      completedFeedbackIds: const [],
      verificationCommands: const [],
      manualVerificationReason: 'Git 撤销待人工确认',
      gitRevertCommit: target,
    );
    final sessionId = _jsonOf(ready)['sessionId'] as String;
    final store = DispatchPendingStore();
    final declared = (await store.read(sessionId))!;
    expect(declared.gitRevertCommit, target);
    await store
        .write(declared.copyWith(status: DispatchPendingStatus.validated));

    final result = await dispatchFinalize(
      controller,
      workerToken: 'worker-a',
      sessionId: sessionId,
    );

    expect(result.isError, isNot(true));
    expect(_jsonOf(result)['status'], 'finalized');
    expect(
      (await File(p.join(repo, 'app.txt')).readAsString())
          .replaceAll('\r\n', '\n'),
      'initial\n',
    );
    final log = await Process.run(
      'git',
      ['log', '-1', '--format=%s'],
      workingDirectory: repo,
    );
    expect(log.stdout.toString().trim(), 'Revert $target');
  });

  test('ready 拒绝非提交哈希的受控撤销声明', () async {
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '非法撤销声明'))!;
    gate.beginBatch('worker-a', projectId: controller.activeProjectId!);
    await dispatchClaimNextCard(controller, workerToken: 'worker-a');

    final result = await dispatchReadyToSubmit(
      controller,
      workerToken: 'worker-a',
      cardId: cardId,
      completedChecklistIds: const [],
      completedFeedbackIds: const [],
      verificationCommands: const [],
      gitRevertCommit: 'HEAD~1',
    );

    expect(result.isError, isTrue);
    expect(
      result.content.whereType<TextContent>().first.text,
      contains('gitRevertCommit'),
    );
  });

  test('新 Worker 仅能恢复同 project/repo 的 committed 事务', () async {
    final repo = await _createGitRepo(tempDir, 'recover_repo');
    final projectId = controller.activeProjectId!;
    final store = DispatchPendingStore();
    await store.write(DispatchPendingRecord(
      sessionId: 'recover-session',
      workerToken: 'old-worker',
      projectId: projectId,
      cardId: 'card-a',
      status: DispatchPendingStatus.committed,
      completedChecklistIds: const [],
      completedFeedbackIds: const [],
      verificationCommands: const [],
      repoPath: repo,
      updatedAt: 1,
    ));
    gate.beginBatch(
      'new-worker',
      projectId: projectId,
      repoPath: repo,
    );

    final listed = await dispatchListPending(
      workerToken: 'new-worker',
      pendingStore: store,
    );
    final pending = _jsonOf(listed)['pending'] as List<dynamic>;
    expect(pending, hasLength(1));

    final recovered = await dispatchRecover(
      workerToken: 'new-worker',
      sessionId: 'recover-session',
      pendingStore: store,
    );
    expect(recovered.isError, isNot(true));
    expect(_jsonOf(recovered)['sessionId'], 'recover-session');
    expect(_jsonOf(recovered)['status'], 'committed');
  });

  test('恢复拒绝 repoPath 不匹配的 pending', () async {
    final projectId = controller.activeProjectId!;
    final store = DispatchPendingStore();
    await store.write(DispatchPendingRecord(
      sessionId: 'wrong-repo-session',
      workerToken: 'old-worker',
      projectId: projectId,
      cardId: 'card-a',
      status: DispatchPendingStatus.committed,
      completedChecklistIds: const [],
      completedFeedbackIds: const [],
      verificationCommands: const [],
      repoPath: p.join(tempDir.path, 'old-repo'),
      updatedAt: 1,
    ));
    gate.beginBatch(
      'new-worker',
      projectId: projectId,
      repoPath: p.join(tempDir.path, 'new-repo'),
    );

    final recovered = await dispatchRecover(
      workerToken: 'new-worker',
      sessionId: 'wrong-repo-session',
      pendingStore: store,
    );

    expect(recovered.isError, isTrue);
    expect(
      (await store.read('wrong-repo-session'))?.status,
      DispatchPendingStatus.committed,
    );
  });

  test('完整 MCP guard 在 claim 锁定期间拒绝送验与阻塞', () async {
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '锁定卡'))!;
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
    );
    await dispatchClaimNextCard(controller, workerToken: 'worker-a');

    expect(
      rejectLockedCardFromFullMcp(cardId, operation: 'submit_card_for_verify'),
      isNotNull,
    );
    expect(
      rejectLockedCardFromFullMcp(cardId, operation: 'block_card'),
      isNotNull,
    );
    expect(
      rejectLockedCardFromFullMcp(
        cardId,
        operation: 'update_card(checklist/verificationFeedback)',
      ),
      isNotNull,
    );
    expect(
      rejectLockedCardFromFullMcp(cardId, operation: 'move_card'),
      isNotNull,
    );
    expect(
      rejectLockedCardFromFullMcp(cardId, operation: 'complete_card'),
      isNotNull,
    );
    expect(
      rejectLockedCardFromFullMcp(cardId, operation: 'delete_card'),
      isNotNull,
    );
    expect(
      rejectLockedCardFromFullMcp(cardId, operation: 'set_card_commit_ref'),
      isNotNull,
    );
    expect(
      rejectLockedCardFromFullMcp('other-card', operation: 'block_card'),
      isNull,
    );
  });

  test('skip 把已 claim 的孤儿卡移入阻塞中', () async {
    final todo =
        controller.board!.columns.firstWhere((item) => item.id == 'todo');
    final cardId = (await controller.addCard(todo.id, '跳过卡'))!;
    gate.beginBatch(
      'worker-a',
      projectId: controller.activeProjectId!,
    );
    final claimed = await dispatchClaimNextCard(
      controller,
      workerToken: 'worker-a',
    );
    final sessionId = _jsonOf(claimed)['sessionId'] as String;

    final skipped = await dispatchFailOrBlock(
      controller,
      workerToken: 'worker-a',
      sessionId: sessionId,
      reason: '用户请求跳过当前卡片',
      block: true,
    );
    expect(skipped.isError, isNot(true));
    expect(
      controller.board!.columns
          .firstWhere((item) => item.id == 'blocked')
          .cards
          .any((item) => item.id == cardId),
      isTrue,
    );
    expect(
      (await DispatchPendingStore().read(sessionId))?.status,
      DispatchPendingStatus.failed,
    );
  });
}
