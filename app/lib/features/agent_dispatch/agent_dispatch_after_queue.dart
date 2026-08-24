import 'dart:io';

import '../mcp/mcp_git_commit.dart';

/// 批次全部完成后按顺序执行的动作。
enum AgentDispatchAfterStep {
  webdavUpload,
  gitPush,
  hibernate,
  shutdown;

  String get label => switch (this) {
        AgentDispatchAfterStep.webdavUpload => 'Upload',
        AgentDispatchAfterStep.gitPush => 'Push',
        AgentDispatchAfterStep.hibernate => 'Hibernate',
        AgentDispatchAfterStep.shutdown => 'Shut down',
      };

  static AgentDispatchAfterStep? tryParse(String? name) {
    if (name == null || name.isEmpty) return null;
    if (name == 'sleep') return AgentDispatchAfterStep.hibernate;
    for (final step in AgentDispatchAfterStep.values) {
      if (step.name == name) return step;
    }
    return null;
  }
}

class AgentDispatchAfterQueueHost {
  const AgentDispatchAfterQueueHost({
    required this.uploadAll,
    required this.gitPush,
    required this.hibernate,
    required this.shutdown,
  });

  final Future<void> Function() uploadAll;
  final Future<void> Function() gitPush;
  final Future<void> Function() hibernate;
  final Future<void> Function() shutdown;
}

List<AgentDispatchAfterStep> parseAgentDispatchAfterQueue(Object? raw) {
  if (raw is! List) return const [];
  final steps = <AgentDispatchAfterStep>[];
  final seen = <AgentDispatchAfterStep>{};
  for (final item in raw) {
    final step = AgentDispatchAfterStep.tryParse('$item');
    if (step == null || seen.contains(step)) continue;
    seen.add(step);
    steps.add(step);
  }
  return List<AgentDispatchAfterStep>.unmodifiable(steps);
}

List<AgentDispatchAfterStep> addAfterQueueStep(
  List<AgentDispatchAfterStep> current,
  AgentDispatchAfterStep step,
) {
  if (current.contains(step)) return current;
  return List<AgentDispatchAfterStep>.unmodifiable([...current, step]);
}

List<AgentDispatchAfterStep> removeAfterQueueStepAt(
  List<AgentDispatchAfterStep> current,
  int index,
) {
  if (index < 0 || index >= current.length) return current;
  final next = [...current]..removeAt(index);
  return List<AgentDispatchAfterStep>.unmodifiable(next);
}

List<AgentDispatchAfterStep> reorderAfterQueueStep(
  List<AgentDispatchAfterStep> current,
  int oldIndex,
  int newIndex,
) {
  if (oldIndex < 0 || oldIndex >= current.length) return current;
  var target = newIndex;
  if (target > oldIndex) target -= 1;
  if (target < 0 || target >= current.length) return current;
  final next = [...current];
  final item = next.removeAt(oldIndex);
  next.insert(target, item);
  return List<AgentDispatchAfterStep>.unmodifiable(next);
}

/// 批次结束时要执行的完成后队列快照。
typedef AgentDispatchAfterQueueSnapshot = ({
  List<AgentDispatchAfterStep> steps,
  bool runOnFailure,
});

/// 批次结束时解析完成后队列：以 [resolved]（最新配置）为准，缺省则用运行中快照。
///
/// 运行过程中的增删改应在结束时重新取最新状态，而不是沿用启动时的旧列表。
AgentDispatchAfterQueueSnapshot resolveAfterQueueForBatchEnd({
  required List<AgentDispatchAfterStep> liveSteps,
  required bool liveRunOnFailure,
  AgentDispatchAfterQueueSnapshot? resolved,
}) {
  if (resolved != null) {
    return (
      steps: List<AgentDispatchAfterStep>.unmodifiable(resolved.steps),
      runOnFailure: resolved.runOnFailure,
    );
  }
  return (
    steps: List<AgentDispatchAfterStep>.unmodifiable(liveSteps),
    runOnFailure: liveRunOnFailure,
  );
}

/// 是否应执行完成后队列。
///
/// 手动停止或「本轮结束后停止」不触发。批次成功始终触发。
/// 已启动 Worker 后因配额、网络等失败时，由 [runOnFailure] 决定（默认勾选）。
bool shouldRunAgentDispatchAfterQueue({
  required bool batchOk,
  required bool cancelRequested,
  required bool drainRequested,
  required bool runOnFailure,
  required bool workerInvoked,
  required bool queueNonEmpty,
}) {
  if (!queueNonEmpty) return false;
  if (cancelRequested || drainRequested) return false;
  if (batchOk) return true;
  return runOnFailure && workerInvoked;
}

/// 按顺序执行完成后队列。任一步失败即停止，后续（含休眠/关机）不会执行。
Future<void> runAgentDispatchAfterQueue({
  required List<AgentDispatchAfterStep> steps,
  required AgentDispatchAfterQueueHost host,
  void Function(String message)? onLog,
}) async {
  for (final step in steps) {
    onLog?.call('Completion queue: starting “${step.label}”');
    switch (step) {
      case AgentDispatchAfterStep.webdavUpload:
        await host.uploadAll();
      case AgentDispatchAfterStep.gitPush:
        await host.gitPush();
      case AgentDispatchAfterStep.hibernate:
        await host.hibernate();
      case AgentDispatchAfterStep.shutdown:
        await host.shutdown();
    }
    onLog?.call('Completion queue: completed “${step.label}”');
  }
}

/// 取消可能残留的延时关机，避免下次开机立刻休眠/关机。
Future<void> abortStaleWindowsPowerAction() async {
  if (!Platform.isWindows) return;
  await Process.run('shutdown', ['/a']);
}

Future<void> windowsHibernateNow({
  Future<ProcessResult> Function(String executable, List<String> arguments)?
      runner,
}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Hibernate is supported only on Windows');
  }
  // shutdown /h 进入 S4 休眠；/h 不支持 /t 延时，也不会留下跨重启的关机倒计时。
  // 不用 SetSuspendState(Suspend/Hibernate)：后者在部分系统上会退化为 S3 睡眠。
  final result = await (runner ?? Process.run)(
    'shutdown',
    const ['/h'],
  );
  if (result.exitCode != 0) {
    final err = '${result.stderr}'.trim();
    throw Exception(err.isEmpty
        ? 'Hibernate command failed (exit ${result.exitCode})'
        : err);
  }
}

Future<void> windowsShutdownNow() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Shutdown is supported only on Windows');
  }
  // /t 0 立即关机，不留下跨重启仍有效的倒计时。
  final result = await Process.run('shutdown', ['/s', '/t', '0']);
  if (result.exitCode != 0) {
    final err = '${result.stderr}'.trim();
    throw Exception(err.isEmpty
        ? 'Shutdown command failed (exit ${result.exitCode})'
        : err);
  }
}

typedef AgentDispatchGitRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

Future<ProcessResult> _defaultGitRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) =>
    Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );

String _gitText(ProcessResult result) {
  final err = '${result.stderr}'.trim();
  if (err.isNotEmpty) return err;
  return '${result.stdout}'.trim();
}

Never _gitFail(String action, ProcessResult result) {
  final detail = _gitText(result);
  throw Exception(
    detail.isEmpty
        ? '$action failed (exit ${result.exitCode})'
        : '$action failed: $detail',
  );
}

bool _gitArgHasForce(List<String> arguments) {
  return arguments.any(
    (arg) =>
        arg == '--force' ||
        arg == '-f' ||
        arg == '--force-with-lease' ||
        arg.startsWith('--force-with-lease='),
  );
}

/// 在工作区干净时 fetch，必要时 merge（可快进则快进），再普通 push。冲突则 abort，永不 force。
Future<void> gitPushWithRebase({
  required String repoPath,
  AgentDispatchGitRunner? runner,
}) async {
  final run = runner ?? _defaultGitRunner;
  final repo = repoPath.trim();
  if (repo.isEmpty) {
    throw Exception('Repository path is empty; cannot push');
  }
  await refreshMcpGitAuthorIdentity();

  Future<ProcessResult> git(List<String> arguments) {
    if (_gitArgHasForce(arguments)) {
      throw Exception('Git arguments containing force were rejected');
    }
    return run(
      'git',
      arguments,
      workingDirectory: repo,
      environment: mcpGitEnvironment(),
    );
  }

  Future<ProcessResult> gitOk(List<String> arguments, String action) async {
    final result = await git(arguments);
    if (result.exitCode != 0) _gitFail(action, result);
    return result;
  }

  final inside = await git(['rev-parse', '--is-inside-work-tree']);
  if (inside.exitCode != 0 || '${inside.stdout}'.trim() != 'true') {
    throw Exception('Not a Git repository: $repo');
  }

  final status = await gitOk(['status', '--porcelain'], 'Check working tree');
  if ('${status.stdout}'.trim().isNotEmpty) {
    throw Exception(
        'Working tree is dirty; push aborted (no auto-commit or force push)');
  }

  for (final marker in const [
    'REBASE_HEAD',
    'MERGE_HEAD',
    'CHERRY_PICK_HEAD'
  ]) {
    final inProgress = await git(['rev-parse', '-q', '--verify', marker]);
    if (inProgress.exitCode == 0) {
      throw Exception(
          '$marker is already in progress; aborted to preserve state');
    }
  }

  final branch =
      await gitOk(['rev-parse', '--abbrev-ref', 'HEAD'], 'Read current branch');
  final branchName = '${branch.stdout}'.trim();
  if (branchName.isEmpty || branchName == 'HEAD') {
    throw Exception('HEAD is detached; push aborted');
  }

  final upstream = await git([
    'rev-parse',
    '--abbrev-ref',
    '--symbolic-full-name',
    '@{u}',
  ]);
  if (upstream.exitCode != 0) {
    throw Exception(
        'Current branch has no upstream; push aborted (origin not set automatically)');
  }

  final remote = await gitOk(
    ['config', '--get', 'branch.$branchName.remote'],
    'Read upstream remote',
  );
  await gitOk(['fetch', '--', '${remote.stdout}'.trim()], 'fetch');

  Future<(int ahead, int behind)> divergence() async {
    final counts = await gitOk(
      ['rev-list', '--left-right', '--count', 'HEAD...@{u}'],
      'Compare with upstream',
    );
    final parts = '${counts.stdout}'.trim().split(RegExp(r'\s+'));
    if (parts.length != 2) {
      throw Exception('Could not parse upstream divergence: ${counts.stdout}');
    }
    return (int.parse(parts[0]), int.parse(parts[1]));
  }

  var (ahead, behind) = await divergence();
  if (behind > 0) {
    if (ahead == 0) {
      await gitOk(['merge', '--ff-only', '@{u}'], 'Fast-forward to upstream');
    } else {
      final merge = await git(['merge', '--no-edit', '@{u}']);
      if (merge.exitCode != 0) {
        await git(['merge', '--abort']);
        final detail = _gitText(merge);
        throw Exception(
          detail.isEmpty
              ? 'Merge conflict or failure; aborted, nothing pushed'
              : 'Merge conflict or failure; aborted, nothing pushed: $detail',
        );
      }
    }
    (ahead, behind) = await divergence();
  }

  if (behind > 0) {
    throw Exception('Still behind upstream after merge; push aborted');
  }
  if (ahead == 0) return;

  await gitOk(['push'], 'push');
}
