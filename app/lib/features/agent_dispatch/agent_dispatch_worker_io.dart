import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'agent_dispatch_config.dart';

class AgentWorkerResult {
  const AgentWorkerResult({
    required this.ok,
    this.summary,
    this.error,
    this.exitCode,
  });

  final bool ok;
  final String? summary;
  final String? error;
  final int? exitCode;
}

/// 解析 `scripts/agent_dispatch/dist/cli.js`。
Future<String?> resolveAgentDispatchCliPath(String? overridePath) async {
  final candidates = <String>[
    if (overridePath != null && overridePath.trim().isNotEmpty)
      overridePath.trim(),
    if ((Platform.environment['KANBAN_ROOT'] ?? '').isNotEmpty)
      p.join(
        Platform.environment['KANBAN_ROOT']!,
        'scripts',
        'agent_dispatch',
        'dist',
        'cli.js',
      ),
    p.join(Directory.current.path, 'scripts', 'agent_dispatch', 'dist', 'cli.js'),
    p.join(
      Directory.current.path,
      '..',
      'scripts',
      'agent_dispatch',
      'dist',
      'cli.js',
    ),
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
  String? model,
  AgentDispatchEffort effort = AgentDispatchEffort.default_,
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async {
  final cli = await resolveAgentDispatchCliPath(workerScriptPath);
  if (cli == null) {
    return const AgentWorkerResult(
      ok: false,
      error:
          '未找到 scripts/agent_dispatch/dist/cli.js。请在仓库 scripts/agent_dispatch 执行 npm install && npm run build，或设置 KANBAN_ROOT / worker 路径。',
    );
  }

  final tempDir = await Directory.systemTemp.createTemp('kanban_agent_');
  final jobFile = File(p.join(tempDir.path, 'job.json'));
  final outFile = File(p.join(tempDir.path, 'out.json'));
  final job = <String, dynamic>{
    'engine': engine.name,
    'cwd': cwd,
    'prompt': prompt,
    if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
    'effort': effort.wireName,
    'outPath': outFile.path,
  };
  await jobFile.writeAsString(jsonEncode(job));

  try {
    final node = await _resolveNodeExecutable();
    if (node == null) {
      return const AgentWorkerResult(
        ok: false,
        error: '未找到 node。请安装 Node.js 并确保在 PATH 中。',
      );
    }
    onLog?.call('启动 worker：$cli');
    final packageRoot = p.basename(p.dirname(cli)) == 'dist'
        ? p.dirname(p.dirname(cli))
        : p.dirname(cli);
    final process = await Process.start(
      node,
      [cli, '--job', jobFile.path],
      workingDirectory: packageRoot,
      environment: Platform.environment,
      runInShell: Platform.isWindows,
    );
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog?.call(line));
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog?.call('[err] $line'));
    final code = await process.exitCode;
    if (await outFile.exists()) {
      try {
        final map = jsonDecode(await outFile.readAsString())
            as Map<String, dynamic>;
        final ok = map['ok'] == true;
        return AgentWorkerResult(
          ok: ok,
          summary: map['summary'] as String?,
          error: map['error'] as String?,
          exitCode: code,
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
      error: code == 0 ? null : 'worker 退出码 $code，且无 out.json',
      exitCode: code,
    );
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}

Future<String?> _resolveNodeExecutable() async {
  for (final name in Platform.isWindows
      ? <String>['node.exe', 'node']
      : <String>['node']) {
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
