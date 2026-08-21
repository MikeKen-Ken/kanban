import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Worker 自包含运行时的诊断结果。
class AgentWorkerHealth {
  const AgentWorkerHealth({
    required this.ok,
    required this.source,
    required this.workerRoot,
    this.nodePath,
    this.nodeVersion,
    this.expectedNodeVersion,
    this.cursorSdkVersion,
    this.error,
  });

  final bool ok;
  final String source;
  final String workerRoot;
  final String? nodePath;
  final String? nodeVersion;
  final String? expectedNodeVersion;
  final String? cursorSdkVersion;
  final String? error;

  String get summary {
    final parts = <String>[
      'Source=$source',
      if (nodeVersion != null) 'Node.js=$nodeVersion',
      if (cursorSdkVersion != null) 'Cursor SDK=$cursorSdkVersion',
    ];
    return parts.join('; ');
  }
}

typedef AgentWorkerCommandRunner = Future<dynamic> Function(
  String executable,
  List<String> arguments,
);

Future<AgentWorkerHealth> inspectAgentWorkerRoot({
  required String root,
  required bool published,
  required String? nodePath,
  AgentWorkerCommandRunner? commandRunner,
}) async {
  final source = published ? 'Built-in app' : 'Source checkout';
  if (nodePath == null) {
    return AgentWorkerHealth(
      ok: false,
      source: source,
      workerRoot: root,
      error: published
          ? 'Built-in Worker is missing portable Node.js'
          : 'Node.js was not found in the development environment',
    );
  }
  final runner = commandRunner ?? _runWorkerCommand;
  final nodeVersion = await _readNodeVersion(nodePath, runner);
  final expectedNodeVersion = await _readExpectedNodeVersion(root);
  final sdkVersion = await _readPackageVersion(
    p.join(root, 'node_modules', '@cursor', 'sdk', 'package.json'),
  );
  final requiredFiles = [
    p.join(root, 'dist', 'cli.js'),
    p.join(
      root,
      'node_modules',
      '@modelcontextprotocol',
      'client',
      'package.json',
    ),
    p.join(root, 'node_modules', '@openai', 'codex', 'bin', 'codex.js'),
  ];
  for (final path in requiredFiles) {
    if (!await File(path).exists()) {
      return _failure(
        source: source,
        root: root,
        nodePath: nodePath,
        nodeVersion: nodeVersion,
        expectedNodeVersion: expectedNodeVersion,
        sdkVersion: sdkVersion,
        error: 'Worker files are incomplete: $path',
      );
    }
  }
  if (expectedNodeVersion != null && nodeVersion != expectedNodeVersion) {
    return _failure(
      source: source,
      root: root,
      nodePath: nodePath,
      nodeVersion: nodeVersion,
      expectedNodeVersion: expectedNodeVersion,
      sdkVersion: sdkVersion,
      error:
          'Worker Node.js version mismatch: expected $expectedNodeVersion, got $nodeVersion',
    );
  }
  if (Platform.isWindows) {
    for (final grammar in ['tree-sitter', 'tree-sitter-bash']) {
      final binding = p.join(
        root,
        'node_modules',
        '@cursor',
        'sdk-win32-x64',
        'vendor',
        grammar,
        'binding.node',
      );
      if (!await File(binding).exists()) {
        return _failure(
          source: source,
          root: root,
          nodePath: nodePath,
          nodeVersion: nodeVersion,
          expectedNodeVersion: expectedNodeVersion,
          sdkVersion: sdkVersion,
          error: 'Cursor SDK native module is missing: $binding',
        );
      }
      try {
        final probe = await runner(
          nodePath,
          ['-e', 'require(process.argv[1])', binding],
        );
        if (probe.exitCode != 0) {
          return _failure(
            source: source,
            root: root,
            nodePath: nodePath,
            nodeVersion: nodeVersion,
            expectedNodeVersion: expectedNodeVersion,
            sdkVersion: sdkVersion,
            error: 'Cursor SDK native module health check failed: $grammar '
                '(exit code ${probe.exitCode})',
          );
        }
      } catch (error) {
        return _failure(
          source: source,
          root: root,
          nodePath: nodePath,
          nodeVersion: nodeVersion,
          expectedNodeVersion: expectedNodeVersion,
          sdkVersion: sdkVersion,
          error: 'Unable to start Worker Node.js: $error',
        );
      }
    }
  }
  return AgentWorkerHealth(
    ok: true,
    source: source,
    workerRoot: root,
    nodePath: nodePath,
    nodeVersion: nodeVersion,
    expectedNodeVersion: expectedNodeVersion,
    cursorSdkVersion: sdkVersion,
  );
}

AgentWorkerHealth _failure({
  required String source,
  required String root,
  required String nodePath,
  required String? nodeVersion,
  required String? expectedNodeVersion,
  required String? sdkVersion,
  required String error,
}) =>
    AgentWorkerHealth(
      ok: false,
      source: source,
      workerRoot: root,
      nodePath: nodePath,
      nodeVersion: nodeVersion,
      expectedNodeVersion: expectedNodeVersion,
      cursorSdkVersion: sdkVersion,
      error: error,
    );

Future<ProcessResult> _runWorkerCommand(
  String executable,
  List<String> arguments,
) =>
    Process.run(executable, arguments);

Future<String?> _readNodeVersion(
  String node,
  AgentWorkerCommandRunner runner,
) async {
  try {
    final result = await runner(node, ['--version']);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim().replaceFirst(RegExp(r'^v'), '');
  } catch (_) {
    return null;
  }
}

Future<String?> _readExpectedNodeVersion(String root) async {
  final manifest = File(p.join(root, 'worker_manifest.json'));
  if (await manifest.exists()) {
    final json = jsonDecode(await manifest.readAsString());
    if (json is Map && json['nodeVersion'] is String) {
      return (json['nodeVersion'] as String).trim();
    }
  }
  final versionFile = File(p.join(root, '..', '..', '.node-version'));
  return await versionFile.exists()
      ? (await versionFile.readAsString()).trim()
      : null;
}

Future<String?> _readPackageVersion(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final json = jsonDecode(await file.readAsString());
  return json is Map && json['version'] is String
      ? json['version'] as String
      : null;
}
