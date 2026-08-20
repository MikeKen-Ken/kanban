import 'dart:io';

import 'package:path/path.dart' as p;

import 'agent_dispatch_agent_shell.dart';
import 'agent_dispatch_powershell_install.dart';
import 'agent_dispatch_worker_heap.dart';

export 'agent_dispatch_agent_shell.dart';
export 'agent_dispatch_powershell_msi_install.dart';
export 'agent_dispatch_powershell_install.dart';
export 'agent_dispatch_worker_heap.dart';

const _hkcuEnvironment = r'HKCU\Environment';
const _hklmEnvironment =
    r'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

/// 从 Windows 用户/系统注册表读出的 PATH 与 FLUTTER_ROOT（未展开）。
class WindowsRegistryEnvironment {
  const WindowsRegistryEnvironment({
    this.machinePath = '',
    this.userPath = '',
    this.machineFlutterRoot = '',
    this.userFlutterRoot = '',
  });

  final String machinePath;
  final String userPath;
  final String machineFlutterRoot;
  final String userFlutterRoot;

  bool get hasPath =>
      machinePath.trim().isNotEmpty || userPath.trim().isNotEmpty;
}

class WorkerEnvironmentBuild {
  const WorkerEnvironmentBuild({
    required this.environment,
    required this.summary,
    this.error,
  });

  final Map<String, String> environment;
  final String summary;
  final String? error;

  bool get ok => error == null || error!.trim().isEmpty;
}

typedef RegQueryRunner = ({int exitCode, String stdout}) Function(
  String key,
  String valueName,
);

typedef DirectoryExists = bool Function(String path);

typedef FileExists = bool Function(String path);

/// 组装 Worker 进程环境：合并 Windows 用户/系统 PATH，并加入 FLUTTER_ROOT 与常见 SDK 位置。
WorkerEnvironmentBuild buildWorkerEnvironment({
  required Map<String, String> processEnvironment,
  required String nodeExecutable,
  String? cursorApiKey,
  WindowsRegistryEnvironment? windowsRegistry,
  DirectoryExists? directoryExists,
  FileExists? fileExists,
  String? pathSeparator,
  int? totalPhysicalMemoryMb,
  ShellVersionRunner? shellVersionRunner,
  PowerShellEnsureResult? powerShellEnsure,
}) {
  final environment = <String, String>{
    for (final entry in processEnvironment.entries) entry.key: entry.value,
  };
  final separator = pathSeparator ?? (Platform.isWindows ? ';' : ':');
  final ctx = separator == ';' ? p.windows : p.posix;
  final exists = directoryExists ?? (path) => Directory(path).existsSync();
  final fileIsPresent = fileExists ?? (path) => File(path).existsSync();
  final nodeDir = ctx.dirname(nodeExecutable);
  final originalPath = _envValue(environment, 'Path') ??
      _envValue(environment, 'PATH') ??
      '';

  final flutterRoot = _firstNonEmpty([
    _envValue(environment, 'FLUTTER_ROOT'),
    windowsRegistry?.userFlutterRoot,
    windowsRegistry?.machineFlutterRoot,
  ]);
  final fromRoot = flutterRoot == null
      ? null
      : _flutterBinIfPresent(
          expandWindowsEnvVars(flutterRoot, environment),
          exists,
          ctx,
        );
  final flutterBins = <String>[];
  void addFlutterBin(String? bin) {
    if (bin == null || bin.trim().isEmpty) return;
    final key = separator == ';' ? bin.toLowerCase() : bin;
    if (flutterBins.any(
      (item) => (separator == ';' ? item.toLowerCase() : item) == key,
    )) {
      return;
    }
    flutterBins.add(bin);
  }

  addFlutterBin(fromRoot);
  for (final bin in _wellKnownFlutterBins(environment, exists, ctx)) {
    addFlutterBin(bin);
  }

  final mergedPath = mergePathEntries(
    [
      nodeDir,
      ...flutterBins,
      if (windowsRegistry != null)
        expandWindowsEnvVars(windowsRegistry.machinePath, environment),
      if (windowsRegistry != null)
        expandWindowsEnvVars(windowsRegistry.userPath, environment),
      originalPath,
    ],
    separator: separator,
  );

  environment['Path'] = mergedPath;
  environment['PATH'] = mergedPath;

  PowerShellEnsureResult? resolvedEnsure = powerShellEnsure;
  String? powerShell7;
  String? powerShellError;
  if (separator == ';') {
    if (resolvedEnsure != null) {
      powerShell7 = resolvedEnsure.executable;
      if (!resolvedEnsure.ok) {
        powerShellError = resolvedEnsure.error;
      }
    } else {
      powerShell7 = resolveWindowsPowerShell7(
        environment: environment,
        separator: separator,
        ctx: ctx,
        fileExists: fileIsPresent,
      );
    }
  }
  if (powerShell7 != null) {
    final pwshDir = ctx.dirname(powerShell7);
    final withPwsh = mergePathEntries(
      [pwshDir, environment['Path'] ?? mergedPath],
      separator: separator,
    );
    environment['Path'] = withPwsh;
    environment['PATH'] = withPwsh;
  }
  final agentShell = separator == ';' && powerShell7 != null
      ? describeWindowsCursorAgentShell(
          powerShell7: powerShell7,
          readVersion: shellVersionRunner,
        )
      : null;
  if (flutterRoot != null && flutterRoot.trim().isNotEmpty) {
    environment['FLUTTER_ROOT'] = expandWindowsEnvVars(flutterRoot, environment);
  } else if (flutterBins.isNotEmpty) {
    environment['FLUTTER_ROOT'] = ctx.dirname(flutterBins.first);
  }
  final key = cursorApiKey?.trim();
  if (key != null && key.isNotEmpty) {
    environment['CURSOR_API_KEY'] = key;
  }
  final heapMb = chooseWorkerNodeHeapMb(
    totalPhysicalMb: totalPhysicalMemoryMb,
    explicitHeapMb: parseKanbanWorkerHeapMb(
      _envValue(environment, 'KANBAN_WORKER_HEAP_MB'),
    ),
  );
  environment['NODE_OPTIONS'] = applyWorkerNodeHeapLimit(
    _envValue(environment, 'NODE_OPTIONS'),
    mb: heapMb,
  );

  return WorkerEnvironmentBuild(
    environment: environment,
    summary: _summary(
      mergedWindowsPath: windowsRegistry?.hasPath ?? false,
      flutterBin: flutterBins.isEmpty ? null : flutterBins.first,
      agentShell: agentShell,
      powerShellEnsure: resolvedEnsure,
      nodeHeapMb: parseNodeMaxOldSpaceSizeMb(environment['NODE_OPTIONS']),
      totalPhysicalMb: totalPhysicalMemoryMb,
      heapOverridden: parseNodeMaxOldSpaceSizeMb(
            _envValue(processEnvironment, 'NODE_OPTIONS'),
          ) !=
          null ||
          parseKanbanWorkerHeapMb(
                _envValue(environment, 'KANBAN_WORKER_HEAP_MB'),
              ) !=
              null,
    ),
    error: powerShellError,
  );
}

/// 读取 Windows 用户与系统 PATH / FLUTTER_ROOT；失败时返回空，沿用进程环境。
WindowsRegistryEnvironment readWindowsRegistryEnvironment({
  RegQueryRunner? query,
}) {
  if (!Platform.isWindows && query == null) {
    return const WindowsRegistryEnvironment();
  }
  final run = query ?? _runRegQuery;
  return WindowsRegistryEnvironment(
    machinePath: _queryRegValue(run, _hklmEnvironment, 'Path'),
    userPath: _queryRegValue(run, _hkcuEnvironment, 'Path'),
    machineFlutterRoot: _queryRegValue(run, _hklmEnvironment, 'FLUTTER_ROOT'),
    userFlutterRoot: _queryRegValue(run, _hkcuEnvironment, 'FLUTTER_ROOT'),
  );
}

String mergePathEntries(
  Iterable<String> chunks, {
  required String separator,
}) {
  final seen = <String>{};
  final parts = <String>[];
  for (final chunk in chunks) {
    for (final raw in chunk.split(separator)) {
      final entry = raw.trim();
      if (entry.isEmpty) continue;
      final key = separator == ';' ? entry.toLowerCase() : entry;
      if (!seen.add(key)) continue;
      parts.add(entry);
    }
  }
  return parts.join(separator);
}

String expandWindowsEnvVars(String raw, Map<String, String> environment) {
  if (!raw.contains('%')) return raw;
  return raw.replaceAllMapped(RegExp(r'%([^%]+)%'), (match) {
    final name = match.group(1)!;
    final value = _envValue(environment, name);
    return (value == null || value.isEmpty) ? match.group(0)! : value;
  });
}

String? parseRegQueryValue(String stdout, String valueName) {
  for (final line in stdout.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trimLeft();
    final match = RegExp(
      '^${RegExp.escape(valueName)}\\s+REG_\\w+\\s+(.*)\$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match != null) return match.group(1)?.trim();
  }
  return null;
}

String _queryRegValue(
  RegQueryRunner query,
  String key,
  String valueName,
) {
  try {
    final result = query(key, valueName);
    if (result.exitCode != 0) return '';
    return parseRegQueryValue(result.stdout, valueName) ?? '';
  } catch (_) {
    return '';
  }
}

({int exitCode, String stdout}) _runRegQuery(String key, String valueName) {
  final result = Process.runSync('reg', ['query', key, '/v', valueName]);
  return (exitCode: result.exitCode, stdout: result.stdout.toString());
}

String? _flutterBinIfPresent(
  String flutterRoot,
  DirectoryExists exists,
  p.Context ctx,
) {
  final trimmed = flutterRoot.trim();
  if (trimmed.isEmpty) return null;
  final bin = ctx.join(trimmed, 'bin');
  return exists(bin) ? bin : null;
}

List<String> _wellKnownFlutterBins(
  Map<String, String> environment,
  DirectoryExists exists,
  p.Context ctx,
) {
  final bins = <String>[];
  void add(String bin) {
    if (exists(bin)) bins.add(bin);
  }

  final localAppData = _envValue(environment, 'LOCALAPPDATA');
  if (localAppData != null && localAppData.trim().isNotEmpty) {
    add(ctx.join(
      expandWindowsEnvVars(localAppData, environment),
      'flutter',
      'bin',
    ));
  }
  final home = _envValue(environment, 'USERPROFILE') ??
      _envValue(environment, 'HOME');
  if (home != null && home.trim().isNotEmpty) {
    final expandedHome = expandWindowsEnvVars(home, environment);
    add(ctx.join(expandedHome, 'flutter', 'bin'));
    add(ctx.join(expandedHome, 'fvm', 'default', 'bin'));
  }
  return bins;
}

String? _envValue(Map<String, String> environment, String name) {
  final direct = environment[name];
  if (direct != null) return direct;
  for (final entry in environment.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value;
  }
  return null;
}

String _summary({
  required bool mergedWindowsPath,
  required String? flutterBin,
  WorkerAgentShell? agentShell,
  PowerShellEnsureResult? powerShellEnsure,
  int? nodeHeapMb,
  int? totalPhysicalMb,
  required bool heapOverridden,
}) {
  final buffer = StringBuffer('Worker 环境：');
  if (flutterBin != null && mergedWindowsPath) {
    buffer.write('已合并用户/系统 PATH，并加入 $flutterBin');
  } else if (flutterBin != null) {
    buffer.write('已加入 $flutterBin');
  } else if (mergedWindowsPath) {
    buffer.write('已合并用户/系统 PATH');
  } else {
    buffer.write('沿用看板进程 PATH');
  }
  if (powerShellEnsure?.installAttempted == true) {
    buffer.write('；${powerShellEnsure!.summaryFragment}');
  }
  if (agentShell != null) {
    buffer.write('；${agentShell.summaryFragment}');
  }
  if (nodeHeapMb != null) {
    buffer.write('；Node 堆上限 ${nodeHeapMb}MB');
    if (heapOverridden) {
      buffer.write('（用户指定）');
    } else if (totalPhysicalMb != null && totalPhysicalMb > 0) {
      buffer.write('（本机物理内存 ${totalPhysicalMb}MB 的约 75%）');
    }
  }
  return buffer.toString();
}
