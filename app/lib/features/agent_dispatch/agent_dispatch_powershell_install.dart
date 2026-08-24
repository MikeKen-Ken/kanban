import 'dart:io';

import 'package:path/path.dart' as p;

import 'agent_dispatch_agent_shell.dart';
import 'agent_dispatch_powershell_msi_install.dart';

/// PowerShell 7 就绪检查结果。
class PowerShellEnsureResult {
  const PowerShellEnsureResult({
    this.executable,
    this.installAttempted = false,
    this.installMethod,
    this.installLog,
    this.error,
  });

  final String? executable;
  final bool installAttempted;
  final String? installMethod;
  final String? installLog;
  final String? error;

  bool get ok => executable != null && executable!.trim().isNotEmpty;

  /// 写入 Worker 环境摘要的安装说明。
  String? get summaryFragment {
    if (!installAttempted) return null;
    if (ok) {
      return switch (installMethod) {
        'winget' => 'PowerShell 7 installed through winget',
        'msi' => 'PowerShell 7 installed through MSI',
        _ => 'PowerShell 7 installed',
      };
    }
    return 'Automatic PowerShell 7 installation failed';
  }
}

typedef WingetRunner = ({int exitCode, String stdout, String stderr}) Function(
  List<String> arguments,
);

typedef PowerShellMsiInstaller = Future<PowerShellMsiInstallResult> Function({
  required Map<String, String> environment,
  required p.Context ctx,
});

/// 解析 winget 可执行文件；未安装 App Installer 时返回 null。
String? resolveWingetExecutable({
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
        expandWindowsEnvVars(localAppData, environment),
        'Microsoft',
        'WindowsApps',
        'winget.exe',
      ),
    );
  }

  final pathValue =
      _envValue(environment, 'Path') ?? _envValue(environment, 'PATH') ?? '';
  for (final raw in pathValue.split(separator)) {
    final dir = raw.trim();
    if (dir.isEmpty) continue;
    add(ctx.join(dir, 'winget.exe'));
  }

  final seen = <String>{};
  for (final candidate in candidates) {
    final key = candidate.toLowerCase();
    if (!seen.add(key)) continue;
    if (fileExists(candidate)) return candidate;
  }
  return null;
}

/// Windows 应用执行别名可能是 reparse point，Dart 的 File.existsSync()
/// 在部分 GUI 进程中无法可靠识别；此时通过实际启动结果确认可用性。
bool canRunWindowsExecutable(
  String executable, {
  List<String> arguments = const <String>[],
}) {
  try {
    final result = Process.runSync(executable, arguments);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// 确保本机可用 PowerShell 7：已安装则直接返回；否则 winget → MSI 依次尝试。
Future<PowerShellEnsureResult> ensureWindowsPowerShell7({
  required Map<String, String> environment,
  required String separator,
  required p.Context ctx,
  required ShellFileExists fileExists,
  WingetRunner? winget,
  PowerShellMsiInstaller? msiInstaller,
  bool allowInstall = true,
}) async {
  final existing = resolveWindowsPowerShell7(
    environment: environment,
    separator: separator,
    ctx: ctx,
    fileExists: fileExists,
  );
  if (existing != null) {
    return PowerShellEnsureResult(executable: existing);
  }
  if (!allowInstall) {
    return const PowerShellEnsureResult(
      error:
          'PowerShell 7 (pwsh) not found. Install it before starting Agent Dispatch.',
    );
  }

  final logs = <String>[];
  final wingetExe = resolveWingetExecutable(
    environment: environment,
    separator: separator,
    ctx: ctx,
    fileExists: fileExists,
  );
  if (wingetExe != null) {
    final wingetResult = await _installViaWinget(
      wingetExecutable: wingetExe,
      environment: environment,
      separator: separator,
      ctx: ctx,
      fileExists: fileExists,
      winget: winget,
    );
    if (wingetResult != null) {
      return wingetResult;
    }
    logs.add('pwsh still not found after winget install/upgrade');
  } else {
    logs.add('winget not found (Windows 10/11 App Installer is required)');
  }

  final installMsi = msiInstaller ??
      ({
        required Map<String, String> environment,
        required p.Context ctx,
      }) =>
          installPowerShell7ViaMsi(
            environment: environment,
            ctx: ctx,
          );
  final msi = await installMsi(environment: environment, ctx: ctx);
  if (msi.log != null && msi.log!.trim().isNotEmpty) {
    logs.add(msi.log!.trim());
  }
  if (msi.ok) {
    final resolved = resolveWindowsPowerShell7(
      environment: environment,
      separator: separator,
      ctx: ctx,
      fileExists: fileExists,
    );
    if (resolved != null) {
      return PowerShellEnsureResult(
        executable: resolved,
        installAttempted: true,
        installMethod: 'msi',
        installLog: _clipLog(logs),
      );
    }
    logs.add('MSI install succeeded, but pwsh.exe is still missing');
  } else if (msi.error != null) {
    logs.add(msi.error!);
  }

  return PowerShellEnsureResult(
    installAttempted: true,
    installLog: _clipLog(logs),
    error: _buildInstallFailureMessage(wingetAvailable: wingetExe != null),
  );
}

Future<PowerShellEnsureResult?> _installViaWinget({
  required String wingetExecutable,
  required Map<String, String> environment,
  required String separator,
  required p.Context ctx,
  required ShellFileExists fileExists,
  WingetRunner? winget,
}) async {
  final runWinget = winget ?? (args) => _runWinget(wingetExecutable, args);
  final install = runWinget(const [
    'install',
    '--id',
    'Microsoft.PowerShell',
    '--source',
    'winget',
    '--accept-package-agreements',
    '--accept-source-agreements',
    '--disable-interactivity',
  ]);
  var resolved = resolveWindowsPowerShell7(
    environment: environment,
    separator: separator,
    ctx: ctx,
    fileExists: fileExists,
  );
  if (resolved != null) {
    return PowerShellEnsureResult(
      executable: resolved,
      installAttempted: true,
      installMethod: 'winget',
      installLog: _clipWingetLog(install),
    );
  }

  final upgrade = runWinget(const [
    'upgrade',
    '--id',
    'Microsoft.PowerShell',
    '--source',
    'winget',
    '--accept-package-agreements',
    '--accept-source-agreements',
    '--disable-interactivity',
  ]);
  resolved = resolveWindowsPowerShell7(
    environment: environment,
    separator: separator,
    ctx: ctx,
    fileExists: fileExists,
  );
  if (resolved != null) {
    return PowerShellEnsureResult(
      executable: resolved,
      installAttempted: true,
      installMethod: 'winget',
      installLog: _clipWingetLog(upgrade),
    );
  }

  return null;
}

String _buildInstallFailureMessage({required bool wingetAvailable}) {
  final buffer = StringBuffer(
      'PowerShell 7 not found; automatic installation also failed.');
  if (!wingetAvailable) {
    buffer.write(
      'winget is not installed (install App Installer from Microsoft Store); ',
    );
  }
  buffer.write(
    'Tried winget and the GitHub MSI silent installer. '
    'Install manually with: winget install --id Microsoft.PowerShell, '
    'or download win-x64.msi from https://github.com/PowerShell/PowerShell/releases.',
  );
  return buffer.toString();
}

bool wingetExitLooksSuccessful(int exitCode) {
  return exitCode == 0 || exitCode == -1978335189;
}

String _clipLog(List<String> chunks) {
  final text = chunks.where((item) => item.trim().isNotEmpty).join('；');
  if (text.length <= 400) return text;
  return '${text.substring(0, 397)}...';
}

String _clipWingetLog(
  ({int exitCode, String stdout, String stderr}) first, [
  ({int exitCode, String stdout, String stderr})? second,
]) {
  final buffer = StringBuffer(
    'install exit=${first.exitCode} ${first.stdout.trim()} ${first.stderr.trim()}'
        .trim(),
  );
  if (second != null) {
    buffer.write(
      '；upgrade exit=${second.exitCode} ${second.stdout.trim()} ${second.stderr.trim()}',
    );
  }
  final text = buffer.toString().trim();
  if (text.length <= 400) return text;
  return '${text.substring(0, 397)}...';
}

({int exitCode, String stdout, String stderr}) _runWinget(
  String executable,
  List<String> arguments,
) {
  try {
    final result = Process.runSync(executable, arguments);
    return (
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  } catch (error) {
    return (
      exitCode: 1,
      stdout: '',
      stderr: error.toString(),
    );
  }
}

bool parseKanbanSkipPowerShellEnsure(String? raw) {
  final value = raw?.trim().toLowerCase();
  return value == '1' || value == 'true' || value == 'yes';
}

String? _envValue(Map<String, String> environment, String name) {
  final direct = environment[name];
  if (direct != null) return direct;
  for (final entry in environment.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

String expandWindowsEnvVars(String raw, Map<String, String> environment) {
  if (!raw.contains('%')) return raw;
  return raw.replaceAllMapped(RegExp(r'%([^%]+)%'), (match) {
    final name = match.group(1)!;
    final value = _envValue(environment, name);
    return (value == null || value.isEmpty) ? match.group(0)! : value;
  });
}
