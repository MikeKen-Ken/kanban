import 'agent_dispatch_config.dart';
import 'agent_interaction.dart';
import 'agent_dispatch_usage.dart';
import 'agent_worker_health.dart';

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

  Future<void> requestDrainAfterCurrent() async {}

  Future<void> requestSkipToNext() async {}

  Future<void> writeLiveOverrides(Map<String, dynamic> payload) async {}

  Future<bool> submitInteractionReply({
    required String requestId,
    required String text,
  }) async =>
      false;
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
  Map<String, dynamic> engineDefaults = const {},
  bool ignoreCardParams = false,
  bool allowDirtyWorkspace = false,
  bool enableSandbox = false,
  bool terminateAfterDispatchTerminal = true,
  String? cursorApiKey,
  String? workerScriptPath,
  void Function(String line)? onLog,
  void Function(AgentInteractionEvent event)? onInteraction,
  void Function(AgentWorkerProcess process)? onProcessStarted,
}) async {
  return const AgentWorkerResult(
    ok: false,
    error: 'Local Agent Dispatch is not supported on this platform',
  );
}

Future<String?> resolveAgentDispatchCliPath(String? overridePath) async => null;

Future<AgentWorkerHealth> inspectAgentDispatchWorker(
  String? workerScriptPath, {
  AgentWorkerCommandRunner? commandRunner,
}) async =>
    const AgentWorkerHealth(
      ok: false,
      source: 'Unsupported',
      workerRoot: 'Unknown',
      error: 'Local Agent Dispatch is not supported on this platform',
    );

Future<List<AgentDispatchModelInfo>> listAgentDispatchModels({
  required AgentDispatchEngine engine,
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
  throw StateError('Local Agent Dispatch is not supported on this platform');
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
  AgentWorkerCommandRunner? commandRunner,
}) async =>
    (ok: false, message: 'The current platform is not supported');

String describeWorkerExitWithoutOutput(int code) =>
    'Worker exited with code $code and did not write out.json';
