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
        'winget' => '已通过 winget 安装 PowerShell 7',
        'msi' => '已通过 MSI 安装 PowerShell 7',
        _ => '已安装 PowerShell 7',
      };
    }
    return 'PowerShell 7 自动安装失败';
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

  final pathValue = _envValue(environment, 'Path') ??
      _envValue(environment, 'PATH') ??
      '';
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
      error: '未找到 PowerShell 7（pwsh）。请安装 PowerShell 7 后再启动 Agent 调度。',
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
    logs.add('winget 安装/升级后仍未找到 pwsh');
  } else {
    logs.add('未检测到 winget（需 Windows 10/11 的 App Installer）');
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
    logs.add('MSI 安装成功但仍未找到 pwsh.exe');
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
  final buffer = StringBuffer('未找到 PowerShell 7，自动安装也失败。');
  if (!wingetAvailable) {
    buffer.write(
      ' 本机未安装 winget（可从 Microsoft Store 安装 App Installer）；',
    );
  }
  buffer.write(
    ' 已尝试 winget 与 GitHub MSI 静默安装。'
    '请手动安装：winget install --id Microsoft.PowerShell，'
    '或从 https://github.com/PowerShell/PowerShell/releases 下载 win-x64.msi。',
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
