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

Future<AgentWorkerResult> runAgentWorkerJob({
  required AgentDispatchEngine engine,
  required String cwd,
  required String prompt,
  String? model,
  List<({String id, String value})> modelParams = const [],
  String? cursorApiKey,
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async {
  return const AgentWorkerResult(
    ok: false,
    error: '当前平台不支持本机 Agent 调度',
  );
}

Future<String?> resolveAgentDispatchCliPath(String? overridePath) async => null;

Future<List<AgentDispatchModelInfo>> listAgentDispatchModels({
  String? cursorApiKey,
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async =>
    const [];

Future<({bool ok, String message})> ensureAgentDispatchWorker({
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async =>
    (ok: false, message: '当前平台不支持');
