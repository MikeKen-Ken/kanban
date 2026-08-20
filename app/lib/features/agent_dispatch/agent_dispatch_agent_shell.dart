/// Cursor Agent 实际选用的终端，供调度日志展示名称与版本。
class WorkerAgentShell {
  const WorkerAgentShell({
    required this.displayName,
    required this.executable,
    this.version,
  });

  final String displayName;
  final String executable;
  final String? version;

  /// 写入 Worker 环境摘要的片段。
  String get summaryFragment {
    final ver = version?.trim();
    if (ver != null && ver.isNotEmpty) {
      return 'Cursor Agent 终端：$displayName $ver（$executable）';
    }
    return 'Cursor Agent 终端：$displayName（$executable，版本未知）';
  }
}

typedef ShellVersionRunner = ({int exitCode, String stdout}) Function(
  String executable,
  List<String> arguments,
);

/// Windows 上 Cursor SDK 的终端：优先 Git Bash，否则为系统 PowerShell 5.1。
WorkerAgentShell describeWindowsCursorAgentShell({
  required String? gitBash,
  required String powershellExecutable,
  ShellVersionRunner? readVersion,
}) {
  final bash = gitBash?.trim() ?? '';
  if (bash.isNotEmpty) {
    return WorkerAgentShell(
      displayName: 'Git Bash',
      executable: bash,
      version: readShellVersion(
        readVersion,
        bash,
        const ['--version'],
        parseBashVersion,
      ),
    );
  }
  return WorkerAgentShell(
    displayName: 'Windows PowerShell',
    executable: powershellExecutable,
    version: readShellVersion(
      readVersion,
      powershellExecutable,
      const [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$PSVersionTable.PSVersion.ToString()',
      ],
      parsePowerShellVersion,
    ),
  );
}

String? readShellVersion(
  ShellVersionRunner? readVersion,
  String executable,
  List<String> arguments,
  String? Function(String stdout) parse,
) {
  if (readVersion == null) return null;
  try {
    final result = readVersion(executable, arguments);
    if (result.exitCode != 0) return null;
    return parse(result.stdout);
  } catch (_) {
    return null;
  }
}

String? parseBashVersion(String stdout) {
  final match = RegExp(
    r'version\s+(\d+\.\d+(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(stdout);
  return match?.group(1);
}

String? parsePowerShellVersion(String stdout) {
  final line = stdout
      .split(RegExp(r'\r?\n'))
      .map((item) => item.trim())
      .firstWhere((item) => item.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return null;
  if (!RegExp(r'^\d+\.\d+').hasMatch(line)) return null;
  return line;
}
