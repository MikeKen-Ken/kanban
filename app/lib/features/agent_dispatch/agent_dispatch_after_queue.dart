import 'dart:io';

/// 批次全部完成后按顺序执行的动作。
enum AgentDispatchAfterStep {
  webdavUpload,
  sleep,
  shutdown;

  String get label => switch (this) {
        AgentDispatchAfterStep.webdavUpload => 'WebDAV 全量上传',
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
    required this.sleep,
    required this.shutdown,
  });

  final Future<void> Function() uploadAll;
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
