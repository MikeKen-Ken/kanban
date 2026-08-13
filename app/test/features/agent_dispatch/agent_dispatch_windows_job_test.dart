import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_windows_job.dart';

void main() {
  test('Job 限制包含关闭时终止，并允许子进程脱离', () {
    expect(
      AgentDispatchWindowsJob.jobLimitFlags,
      0x00002000 | 0x00000800,
    );
  });

  test('关闭 Job Object 会终止已绑定的 Worker', () async {
    if (!Platform.isWindows) return;

    final process = await Process.start(
      'cmd.exe',
      ['/c', 'timeout', '/t', '30', '/nobreak'],
    );
    String? warning;
    final job = AgentDispatchWindowsJob.tryAttach(
      process.pid,
      onWarning: (message) => warning = message,
    );
    try {
      // 某些 CI/沙箱会把 flutter_tester 放进不可嵌套的 Job，Windows 会拒绝
      // 二次分配。正式桌面应用仍应尝试绑定，并在该限制下回退 taskkill /T。
      if (job == null) return;
      job.dispose();
      await process.exitCode.timeout(const Duration(seconds: 5));
    } finally {
      job?.dispose();
      if (!await _hasExited(process)) {
        process.kill();
      }
      if (job == null && warning == null) {
        fail('Job Object 绑定失败但未返回降级原因');
      }
    }
  });
}

Future<bool> _hasExited(Process process) async {
  try {
    await process.exitCode.timeout(Duration.zero);
    return true;
  } on TimeoutException {
    return false;
  }
}
