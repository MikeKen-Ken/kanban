import 'agent_dispatch_config.dart';

/// Web/无 IO 平台占位。
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

Future<AgentWorkerResult> runAgentWorkerJob({
  required AgentDispatchEngine engine,
  required String cwd,
  required String prompt,
  String? model,
  AgentDispatchEffort effort = AgentDispatchEffort.default_,
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async {
  return const AgentWorkerResult(
    ok: false,
    error: '当前平台不支持本机 Agent 调度',
  );
}

Future<String?> resolveAgentDispatchCliPath(String? overridePath) async => null;
