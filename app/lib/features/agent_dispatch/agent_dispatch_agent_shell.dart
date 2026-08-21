import 'package:path/path.dart' as p;

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
      return 'Cursor Agent shell: $displayName $ver ($executable)';
    }
    return 'Cursor Agent shell: $displayName ($executable, version unknown)';
  }
}

typedef ShellVersionRunner = ({int exitCode, String stdout}) Function(
  String executable,
  List<String> arguments,
);

typedef ShellFileExists = bool Function(String path);

/// Windows 上 Cursor SDK 的终端：PowerShell 7（pwsh）。
///
/// Cursor Agent 不读取 IDE 的 terminal 设置，而是在 PATH 中查找 `pwsh`；
/// 因此 Worker 需把 pwsh 所在目录前置到 PATH，才能稳定选中 PS7。
WorkerAgentShell describeWindowsCursorAgentShell({
  required String powerShell7,
  ShellVersionRunner? readVersion,
}) {
  final executable = powerShell7.trim();
  return WorkerAgentShell(
    displayName: 'PowerShell 7',
    executable: executable,
    version: readShellVersion(
      readVersion,
      executable,
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

/// 按 Cursor 集成终端「PowerShell 7」配置的候选顺序解析 pwsh.exe。
String? resolveWindowsPowerShell7({
  required Map<String, String> environment,
  required String separator,
  required p.Context ctx,
  required ShellFileExists fileExists,
}) {
  final candidates = <String>[];
  void add(String? path) {
    final trimmed = path?.trim() ?? '';
    if (trimmed.isEmpty) return;
    candidates.add(trimmed);
  }

  final localAppData = _envValue(environment, 'LOCALAPPDATA');
  if (localAppData != null && localAppData.trim().isNotEmpty) {
    add(
      ctx.join(
        _expandWindowsEnvVars(localAppData, environment),
        'Microsoft',
        'WindowsApps',
        'pwsh.exe',
      ),
    );
  }

  for (final name in const ['ProgramFiles', 'ProgramFiles(x86)']) {
    final root = _envValue(environment, name);
    if (root == null || root.trim().isEmpty) continue;
    add(
      ctx.join(
        _expandWindowsEnvVars(root, environment),
        'PowerShell',
        '7',
        'pwsh.exe',
      ),
    );
  }

  final pathValue =
      _envValue(environment, 'Path') ?? _envValue(environment, 'PATH') ?? '';
  for (final raw in pathValue.split(separator)) {
    final dir = raw.trim();
    if (dir.isEmpty) continue;
    add(ctx.join(dir, 'pwsh.exe'));
  }

  final seen = <String>{};
  for (final candidate in candidates) {
    final key = candidate.toLowerCase();
    if (!seen.add(key)) continue;
    if (fileExists(candidate) && _looksLikePwsh(candidate)) {
      return candidate;
    }
  }
  return null;
}

bool _looksLikePwsh(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  return normalized.endsWith('pwsh.exe');
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

String? parsePowerShellVersion(String stdout) {
  final line = stdout
      .split(RegExp(r'\r?\n'))
      .map((item) => item.trim())
      .firstWhere((item) => item.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return null;
  if (!RegExp(r'^\d+\.\d+').hasMatch(line)) return null;
  return line;
}

String? _envValue(Map<String, String> environment, String name) {
  final direct = environment[name];
  if (direct != null) return direct;
  for (final entry in environment.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

String _expandWindowsEnvVars(String raw, Map<String, String> environment) {
  if (!raw.contains('%')) return raw;
  return raw.replaceAllMapped(RegExp(r'%([^%]+)%'), (match) {
    final name = match.group(1)!;
    final value = _envValue(environment, name);
    return (value == null || value.isEmpty) ? match.group(0)! : value;
  });
}
