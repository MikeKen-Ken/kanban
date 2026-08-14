import 'dart:io';

/// 批次全部完成后按顺序执行的动作。
enum AgentDispatchAfterStep {
  webdavUpload,
  gitPush,
  sleep,
  shutdown;

  String get label => switch (this) {
        AgentDispatchAfterStep.webdavUpload => '上传',
        AgentDispatchAfterStep.gitPush => '推送',
        AgentDispatchAfterStep.sleep => '休眠',
        AgentDispatchAfterStep.shutdown => '关机',
      };

  static AgentDispatchAfterStep? tryParse(String? name) {
    if (name == null || name.isEmpty) return null;
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
    required this.sleep,
    required this.shutdown,
  });

  final Future<void> Function() uploadAll;
  final Future<void> Function() gitPush;
  final Future<void> Function() sleep;
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
    onLog?.call('完成后队列：开始「${step.label}」');
    switch (step) {
      case AgentDispatchAfterStep.webdavUpload:
        await host.uploadAll();
      case AgentDispatchAfterStep.gitPush:
        await host.gitPush();
      case AgentDispatchAfterStep.sleep:
        await host.sleep();
      case AgentDispatchAfterStep.shutdown:
        await host.shutdown();
    }
    onLog?.call('完成后队列：已完成「${step.label}」');
  }
}

/// 取消可能残留的延时关机，避免下次开机立刻休眠/关机。
Future<void> abortStaleWindowsPowerAction() async {
  if (!Platform.isWindows) return;
  await Process.run('shutdown', ['/a']);
}

Future<void> windowsSleepNow() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('仅 Windows 支持休眠');
  }
  // 立即进入 S3 睡眠，不创建计划任务或延时关机，因此不会在下次开机重复执行。
  final result = await Process.run(
    'powershell',
    const [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-Command',
      'Add-Type -AssemblyName System.Windows.Forms; '
          '[void][System.Windows.Forms.Application]::SetSuspendState('
          '[System.Windows.Forms.PowerState]::Suspend, \$false, \$false)',
    ],
  );
  if (result.exitCode != 0) {
    final err = '${result.stderr}'.trim();
    throw Exception(err.isEmpty ? '休眠命令失败（exit ${result.exitCode}）' : err);
  }
}

Future<void> windowsShutdownNow() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('仅 Windows 支持关机');
  }
  // /t 0 立即关机，不留下跨重启仍有效的倒计时。
  final result = await Process.run('shutdown', ['/s', '/t', '0']);
  if (result.exitCode != 0) {
    final err = '${result.stderr}'.trim();
    throw Exception(err.isEmpty ? '关机命令失败（exit ${result.exitCode}）' : err);
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
    detail.isEmpty ? '$action失败（exit ${result.exitCode}）' : '$action失败：$detail',
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

/// 在工作区干净时 fetch，必要时 rebase，再普通 push。冲突则 abort，永不 force。
Future<void> gitPushWithRebase({
  required String repoPath,
  AgentDispatchGitRunner? runner,
}) async {
  final run = runner ?? _defaultGitRunner;
  final repo = repoPath.trim();
  if (repo.isEmpty) {
    throw Exception('未填写代码仓库路径，无法推送');
  }

  Future<ProcessResult> git(List<String> arguments) {
    if (_gitArgHasForce(arguments)) {
      throw Exception('已拒绝带 force 的 git 参数');
    }
    return run(
      'git',
      arguments,
      workingDirectory: repo,
      environment: {
        ...Platform.environment,
        'GIT_TERMINAL_PROMPT': '0',
        'GCM_INTERACTIVE': 'Never',
      },
    );
  }

  Future<ProcessResult> gitOk(List<String> arguments, String action) async {
    final result = await git(arguments);
    if (result.exitCode != 0) _gitFail(action, result);
    return result;
  }

  final inside = await git(['rev-parse', '--is-inside-work-tree']);
  if (inside.exitCode != 0 || '${inside.stdout}'.trim() != 'true') {
    throw Exception('不是 Git 仓库：$repo');
  }

  final status = await gitOk(['status', '--porcelain'], '检查工作区');
  if ('${status.stdout}'.trim().isNotEmpty) {
    throw Exception('工作区不干净，已中止推送（不会自动提交或 force push）');
  }

  for (final marker in const ['REBASE_HEAD', 'MERGE_HEAD', 'CHERRY_PICK_HEAD']) {
    final inProgress = await git(['rev-parse', '-q', '--verify', marker]);
    if (inProgress.exitCode == 0) {
      throw Exception('已有 $marker 进行中，已中止以免破坏现有状态');
    }
  }

  final branch = await gitOk(['rev-parse', '--abbrev-ref', 'HEAD'], '读取当前分支');
  final branchName = '${branch.stdout}'.trim();
  if (branchName.isEmpty || branchName == 'HEAD') {
    throw Exception('当前处于游离 HEAD，已中止推送');
  }

  final upstream = await git([
    'rev-parse',
    '--abbrev-ref',
    '--symbolic-full-name',
    '@{u}',
  ]);
  if (upstream.exitCode != 0) {
    throw Exception('当前分支没有上游，已中止推送（不会自动设置 origin）');
  }

  final remote = await gitOk(
    ['config', '--get', 'branch.$branchName.remote'],
    '读取上游远程',
  );
  await gitOk(['fetch', '--', '${remote.stdout}'.trim()], 'fetch');

  Future<(int ahead, int behind)> divergence() async {
    final counts = await gitOk(
      ['rev-list', '--left-right', '--count', 'HEAD...@{u}'],
      '比较与上游的差异',
    );
    final parts = '${counts.stdout}'.trim().split(RegExp(r'\s+'));
    if (parts.length != 2) {
      throw Exception('无法解析与上游的差异：${counts.stdout}');
    }
    return (int.parse(parts[0]), int.parse(parts[1]));
  }

  var (ahead, behind) = await divergence();
  if (behind > 0) {
    if (ahead == 0) {
      await gitOk(['merge', '--ff-only', '@{u}'], '快进到上游');
    } else {
      final rebase = await git(['rebase', '@{u}']);
      if (rebase.exitCode != 0) {
        await git(['rebase', '--abort']);
        final detail = _gitText(rebase);
        throw Exception(
          detail.isEmpty
              ? 'rebase 冲突或失败，已 abort，未推送'
              : 'rebase 冲突或失败，已 abort，未推送：$detail',
        );
      }
    }
    (ahead, behind) = await divergence();
  }

  if (behind > 0) {
    throw Exception('rebase 后仍落后上游，已中止推送');
  }
  if (ahead == 0) return;

  await gitOk(['push'], 'push');
}
