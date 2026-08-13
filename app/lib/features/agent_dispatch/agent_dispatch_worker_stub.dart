import 'agent_dispatch_config.dart';
import 'agent_dispatch_usage.dart';

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

class AgentWorkerProcess {
  const AgentWorkerProcess();

  Future<void> stop() async {}
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

Future<AgentDispatchUsageSnapshot> fetchAgentDispatchUsage({
  String? cursorApiKey,
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async {
  throw StateError('当前平台不支持本机 Agent 调度');
}

Future<String?> resolveCursorApiKeyLabel({
  required String cursorApiKey,
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async =>
    null;

Future<({bool ok, String message})> ensureAgentDispatchWorker({
  String? workerScriptPath,
  void Function(String line)? onLog,
}) async =>
    (ok: false, message: '当前平台不支持');

String describeWorkerExitWithoutOutput(int code) =>
    'worker 退出码 $code，且无 out.json';
