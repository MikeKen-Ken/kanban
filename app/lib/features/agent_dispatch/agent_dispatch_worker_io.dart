import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'agent_dispatch_config.dart';
import 'agent_dispatch_usage.dart';
import 'agent_dispatch_windows_job.dart';

class AgentWorkerResult {
  const AgentWorkerResult({
    required this.ok,
    this.summary,
    this.error,
    this.exitCode,
    this.processedCards,
  });

  final bool ok;
  final String? summary;
  final String? error;
  final int? exitCode;
  final int? processedCards;
}

/// 当前 Worker 及其 Agent 子进程的可终止句柄。
class AgentWorkerProcess {
  AgentWorkerProcess(this._process, {AgentDispatchWindowsJob? windowsJob})
      : _windowsJob = windowsJob;

  final Process _process;
  AgentDispatchWindowsJob? _windowsJob;
  bool _stopRequested = false;

  /// 终止 Worker 及其启动的 SDK/CLI 子进程。
  Future<void> stop() async {
    if (_stopRequested) return;
    _stopRequested = true;
    _windowsJob?.dispose();
    _windowsJob = null;
    if (Platform.isWindows) {
      await Process.run(
        'taskkill',
        ['/PID', '${_process.pid}', '/T', '/F'],
        runInShell: true,
      );
      return;
    }
    _process.kill(ProcessSignal.sigterm);
  }

  /// Worker 正常结束后释放 Job 句柄；若仍有意外存活的子进程则一并终止。
  void dispose() {
    _windowsJob?.dispose();
    _windowsJob = null;
  }
}

Future<String?> resolveAgentDispatchPackageRoot(String? overrideCli) async {
  final cli = await resolveAgentDispatchCliPath(overrideCli);
  if (cli != null) {
    final dir = p.dirname(cli);
    return p.basename(dir) == 'dist' ? p.dirname(dir) : dir;
  }
  for (final candidate in _packageRootCandidates()) {
    final pkg = p.join(candidate, 'package.json');
    if (await File(pkg).exists()) return candidate;
  }
  return null;
}

Iterable<String> _packageRootCandidates() sync* {
  final kanbanRoot = Platform.environment['KANBAN_ROOT'];
  if (kanbanRoot != null && kanbanRoot.isNotEmpty) {
    yield p.join(kanbanRoot, 'scripts', 'agent_dispatch');
  }
  final executableDir = p.dirname(Platform.resolvedExecutable);
  yield p.join(executableDir, 'agent_worker');
  yield p.join(executableDir, 'scripts', 'agent_dispatch');
  yield p.join(Directory.current.path, 'scripts', 'agent_dispatch');
  yield p.join(Directory.current.path, '..', 'scripts', 'agent_dispatch');
}

Future<String?> resolveAgentDispatchCliPath(String? overridePath) async {
  final candidates = <String>[
    if (overridePath != null && overridePath.trim().isNotEmpty)
      overridePath.trim(),
    for (final root in _packageRootCandidates()) p.join(root, 'dist', 'cli.js'),
  ];
  for (final path in candidates) {
    final normalized = p.normalize(path);
    if (await File(normalized).exists()) return normalized;
  }
  return null;
}

Future<AgentWorkerResult> runAgentWorkerJob({
  required AgentDispatchEngine engine,
  required String cwd,
  required String prompt,
  required String mcpEndpoint,
  required int cardLimit,
  required String workerToken,
  String? projectId,
  String? model,
  List<({String id, String value})> modelParams = const [],
  String? cursorApiKey,
  String? workerScriptPath,
  void Function(String line)? onLog,
  void Function(AgentWorkerProcess process)? onProcessStarted,
}) async {
  final cli = await resolveAgentDispatchCliPath(workerScriptPath);
  if (cli == null) {
    return const AgentWorkerResult(
      ok: false,
      error: '未找到 Worker（dist/cli.js）。请点「一键修复 Worker」。',
    );
  }

  final tempDir = await Directory.systemTemp.createTemp('kanban_agent_');
  final jobFile = File(p.join(tempDir.path, 'job.json'));
  final outFile = File(p.join(tempDir.path, 'out.json'));
  final job = <String, dynamic>{
    'engine': engine.name,
    'cwd': cwd,
    'prompt': prompt,
    'mcpEndpoint': mcpEndpoint,
    'cardLimit': cardLimit,
    'workerToken': workerToken,
    if (projectId != null && projectId.trim().isNotEmpty)
      'projectId': projectId.trim(),
    if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
    if (modelParams.isNotEmpty)
      'modelParams': [
        for (final item in modelParams) {'id': item.id, 'value': item.value},
      ],
    'outPath': outFile.path,
  };
  await jobFile.writeAsString(jsonEncode(job));

  try {
    final packageRoot = p.basename(p.dirname(cli)) == 'dist'
        ? p.dirname(p.dirname(cli))
        : p.dirname(cli);
    final node = await _resolveNodeExecutable(packageRoot: packageRoot);
    if (node == null) {
      return const AgentWorkerResult(
        ok: false,
        error: '未找到 node。请安装 Node.js 并确保在 PATH 中。',
      );
    }
    onLog?.call('启动 worker：$cli');
    onLog?.call('node：$node');
    final environment = _workerEnvironment(
      nodeExecutable: node,
      cursorApiKey: cursorApiKey,
    );
    final process = await Process.start(
      node,
      [cli, '--job', jobFile.path],
      workingDirectory: packageRoot,
      environment: environment,
    );
    final workerProcess = AgentWorkerProcess(
      process,
      windowsJob: AgentDispatchWindowsJob.tryAttach(
        process.pid,
        onWarning: (message) => onLog?.call('[warning] $message'),
      ),
    );
    onProcessStarted?.call(workerProcess);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog?.call(line));
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog?.call('[err] $line'));
    final code = await process.exitCode;
    workerProcess.dispose();
    if (await outFile.exists()) {
      try {
        final map =
            jsonDecode(await outFile.readAsString()) as Map<String, dynamic>;
        return AgentWorkerResult(
          ok: map['ok'] == true,
          summary: map['summary'] as String?,
          error: map['error'] as String?,
          exitCode: code,
          processedCards: (map['processedCards'] as num?)?.toInt(),
        );
      } catch (e) {
        return AgentWorkerResult(
          ok: false,
          error: '解析 worker 输出失败：$e',
          exitCode: code,
        );
      }
    }
    return AgentWorkerResult(
      ok: code == 0,
      error: code == 0 ? null : describeWorkerExitWithoutOutput(code),
      exitCode: code,
    );
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}

Future<List<AgentDispatchModelInfo>> listAgentDispatchModels({
  String? cursorApiKey,
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async {
  final cli = await resolveAgentDispatchCliPath(workerScriptPath);
  if (cli == null) {
    throw StateError('未找到 Worker，请先一键修复');
  }
  final packageRoot = p.basename(p.dirname(cli)) == 'dist'
      ? p.dirname(p.dirname(cli))
      : p.dirname(cli);
  final node = await _resolveNodeExecutable(packageRoot: packageRoot);
  if (node == null) throw StateError('未找到 node');
  if (cursorApiKey == null || cursorApiKey.trim().isEmpty) {
    throw StateError('尚未配置 Cursor API Key');
  }
  final environment = _workerEnvironment(
    nodeExecutable: node,
    cursorApiKey: cursorApiKey,
  );
  onLog?.call('拉取模型列表…');
  final result = await Process.run(
    node,
    [cli, '--list-models'],
    workingDirectory: packageRoot,
    environment: environment,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    final err = (result.stderr as String).trim();
    final firstLine = err
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    throw StateError(
      firstLine.isEmpty ? 'list-models 失败（${result.exitCode}）' : firstLine,
    );
  }
  final stdout = (result.stdout as String).trim();
  final map = jsonDecode(stdout) as Map<String, dynamic>;
  final list = map['models'] as List<dynamic>? ?? const [];
  return list
      .whereType<Map<String, dynamic>>()
      .map(AgentDispatchModelInfo.fromJson)
      .where((m) => m.id.isNotEmpty)
      .toList();
}

Future<AgentDispatchUsageSnapshot> fetchAgentDispatchUsage({
  String? cursorApiKey,
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async {
  final cli = await resolveAgentDispatchCliPath(workerScriptPath);
  if (cli == null) {
    throw StateError('未找到 Worker，请先一键修复');
  }
  final packageRoot = p.basename(p.dirname(cli)) == 'dist'
      ? p.dirname(p.dirname(cli))
      : p.dirname(cli);
  final node = await _resolveNodeExecutable(packageRoot: packageRoot);
  if (node == null) throw StateError('未找到 node');
  if (cursorApiKey == null || cursorApiKey.trim().isEmpty) {
    throw StateError('尚未配置 Cursor API Key');
  }
  final environment = _workerEnvironment(
    nodeExecutable: node,
    cursorApiKey: cursorApiKey,
  );
  onLog?.call('拉取 Cursor 额度…');
  final result = await Process.run(
    node,
    [cli, '--usage'],
    workingDirectory: packageRoot,
    environment: environment,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    final err = (result.stderr as String).trim();
    final stdout = (result.stdout as String).trim();
    if (stdout.isNotEmpty) {
      try {
        final map = jsonDecode(stdout) as Map<String, dynamic>;
        return AgentDispatchUsageSnapshot.fromJson(map);
      } catch (_) {}
    }
    throw StateError(err.isEmpty ? 'usage 失败（${result.exitCode}）' : err);
  }
  final stdout = (result.stdout as String).trim();
  final map = jsonDecode(stdout) as Map<String, dynamic>;
  return AgentDispatchUsageSnapshot.fromJson(map);
}

/// 通过 Cursor.me 解析 API Key 显示名；失败时返回 null，由凭据层回退默认别名。
Future<String?> resolveCursorApiKeyLabel({
  required String cursorApiKey,
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async {
  final snapshot = await fetchAgentDispatchUsage(
    cursorApiKey: cursorApiKey,
    workerScriptPath: workerScriptPath,
    onLog: onLog,
  );
  final name = snapshot.apiKeyName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final email = snapshot.userEmail?.trim();
  if (email != null && email.isNotEmpty) return email;
  return null;
}

Future<({bool ok, String message})> ensureAgentDispatchWorker({
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async {
  final existing = await resolveAgentDispatchCliPath(workerScriptPath);
  if (existing != null && await File(existing).exists()) {
    final existingRoot = p.basename(p.dirname(existing)) == 'dist'
        ? p.dirname(p.dirname(existing))
        : p.dirname(existing);
    final cursorSdk = p.join(
      existingRoot,
      'node_modules',
      '@cursor',
      'sdk',
    );
    final mcpClient = p.join(
      existingRoot,
      'node_modules',
      '@modelcontextprotocol',
      'client',
    );
    final codexCli = p.join(
      existingRoot,
      'node_modules',
      '@openai',
      'codex',
      'bin',
      'codex.js',
    );
    final node = await _resolveNodeExecutable(packageRoot: existingRoot);
    if (await Directory(cursorSdk).exists() &&
        await Directory(mcpClient).exists() &&
        await File(codexCli).exists() &&
        node != null) {
      return (ok: true, message: 'Worker 已就绪：$existing');
    }
  }

  final packageRoot = await resolveAgentDispatchPackageRoot(workerScriptPath);
  if (packageRoot == null) {
    return (
      ok: false,
      message: '未找到内置 Worker。开发环境请设置 KANBAN_ROOT；发布包请重新下载完整 ZIP。',
    );
  }

  final npm = await _resolveNpmExecutable();
  if (npm == null) {
    return (ok: false, message: '未找到 npm。请先安装 Node.js。');
  }

  onLog?.call('npm install @ $packageRoot');
  final install = await Process.run(
    npm,
    ['install'],
    workingDirectory: packageRoot,
    environment: Platform.environment,
    runInShell: true,
  );
  onLog?.call((install.stdout as String).trim());
  if ((install.stderr as String).trim().isNotEmpty) {
    onLog?.call((install.stderr as String).trim());
  }
  if (install.exitCode != 0) {
    return (ok: false, message: 'npm install 失败（${install.exitCode}）');
  }

  onLog?.call('npm run build');
  final build = await Process.run(
    npm,
    ['run', 'build'],
    workingDirectory: packageRoot,
    environment: Platform.environment,
    runInShell: true,
  );
  onLog?.call((build.stdout as String).trim());
  if ((build.stderr as String).trim().isNotEmpty) {
    onLog?.call((build.stderr as String).trim());
  }
  if (build.exitCode != 0) {
    return (ok: false, message: 'npm run build 失败（${build.exitCode}）');
  }

  final cli = p.join(packageRoot, 'dist', 'cli.js');
  if (!await File(cli).exists()) {
    return (ok: false, message: '构建完成但仍未找到 dist/cli.js');
  }
  return (ok: true, message: 'Worker 已修复：$cli');
}

/// Worker 在写出 out.json 前被系统杀掉时的说明。
String describeWorkerExitWithoutOutput(int code) {
  // Windows STATUS_ACCESS_VIOLATION
  if (code == -1073741819) {
    return 'worker 在 Windows 上发生访问冲突（0xC0000005）后退出，未能写出 out.json。'
        '通常是 Cursor 本地运行时（沙箱/SQLite）崩溃，而不是业务逻辑返回了错误码。';
  }
  return 'worker 退出码 $code，且无 out.json';
}

Map<String, String> _workerEnvironment({
  required String nodeExecutable,
  String? cursorApiKey,
}) {
  final environment = Map<String, String>.from(Platform.environment);
  final nodeDir = p.dirname(nodeExecutable);
  final original = environment['Path'] ?? environment['PATH'] ?? '';
  final pathListSeparator = Platform.isWindows ? ';' : ':';
  final merged =
      original.isEmpty ? nodeDir : '$nodeDir$pathListSeparator$original';
  environment['Path'] = merged;
  environment['PATH'] = merged;
  if (cursorApiKey != null && cursorApiKey.trim().isNotEmpty) {
    environment['CURSOR_API_KEY'] = cursorApiKey.trim();
  }
  return environment;
}

Future<String?> _resolveNodeExecutable({String? packageRoot}) async {
  if (packageRoot != null) {
    final bundled = p.join(
      packageRoot,
      'runtime',
      Platform.isWindows ? 'node.exe' : 'node',
    );
    if (await File(bundled).exists()) return bundled;
  }
  return _resolveOnPath(
    Platform.isWindows ? const ['node.exe', 'node'] : const ['node'],
  );
}

Future<String?> _resolveNpmExecutable() => _resolveOnPath(
    Platform.isWindows ? const ['npm.cmd', 'npm'] : const ['npm']);

Future<String?> _resolveOnPath(List<String> names) async {
  for (final name in names) {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        [name],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final line = (result.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .firstWhere((e) => e.isNotEmpty, orElse: () => '');
        if (line.isNotEmpty) return line;
      }
    } catch (_) {}
  }
  return null;
}
