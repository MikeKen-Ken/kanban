import 'package:mcp_dart/mcp_dart.dart';

import '../../../controllers/board_controller.dart';
import '../../activity/activity_models.dart';
import '../mcp_arg_parsers.dart';
import '../mcp_dispatch_card_gate.dart';
import '../mcp_tool_results.dart';
import 'dispatch_claim_next_card.dart';
import 'dispatch_finalizer.dart';
import 'dispatch_pending_store.dart';
import 'dispatch_recovery.dart';
import 'dispatch_report_shell_span.dart';
import 'dispatch_session_end.dart';
import 'dispatch_shell_spans.dart';
import 'dispatch_validation_shape.dart';

typedef DispatchScopedEndpointCloser = Future<void> Function(
    String workerToken);

void registerDispatchPrivateTools(
  McpServer server,
  BoardController controller, {
  DispatchScopedEndpointStarter? startScopedEndpoint,
  DispatchScopedEndpointCloser? closeScopedEndpoint,
}) {
  server.registerTool(
    'dispatch_claim_next_card',
    description:
        'Worker-private tool: atomically claim the next card for the project bound to workerToken.',
    inputSchema: JsonSchema.object(
      properties: {
        'workerToken': JsonSchema.string(),
        'expectedCardId': JsonSchema.string(),
      },
      required: ['workerToken'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final token = mcpTrimmedString(args['workerToken']);
      if (token == null) return mcpErrorResult('workerToken cannot be empty');
      if (closeScopedEndpoint != null) await closeScopedEndpoint(token);
      return dispatchClaimNextCard(
        controller,
        workerToken: token,
        expectedCardId: mcpTrimmedString(args['expectedCardId']),
        startScopedEndpoint: startScopedEndpoint,
      );
    },
  );

  server.registerTool(
    'dispatch_list_pending',
    description:
        'Worker-private tool: list pending sessions recoverable for the current project/repository.',
    inputSchema: JsonSchema.object(
      properties: {'workerToken': JsonSchema.string()},
      required: ['workerToken'],
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) {
      final token = mcpTrimmedString(args['workerToken']);
      if (token == null) {
        return Future.value(mcpErrorResult('workerToken cannot be empty'));
      }
      return dispatchListPending(workerToken: token);
    },
  );

  server.registerTool(
    'dispatch_recover',
    description:
        'Worker-private tool: reauthorize a pending session by sessionId for the current project/repository.',
    inputSchema: JsonSchema.object(
      properties: {
        'workerToken': JsonSchema.string(),
        'sessionId': JsonSchema.string(),
      },
      required: ['workerToken', 'sessionId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) {
      final token = mcpTrimmedString(args['workerToken']);
      final sessionId = mcpTrimmedString(args['sessionId']);
      if (token == null || sessionId == null) {
        return Future.value(
          mcpErrorResult('workerToken and sessionId cannot be empty'),
        );
      }
      return dispatchRecover(workerToken: token, sessionId: sessionId);
    },
  );

  server.registerTool(
    'dispatch_agent_session_status',
    description: 'Worker-private tool: read claim and pending status.',
    inputSchema: JsonSchema.object(
      properties: {'workerToken': JsonSchema.string()},
      required: ['workerToken'],
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final token = mcpTrimmedString(args['workerToken']);
      final status = token == null
          ? null
          : McpDispatchCardGate.instance.sessionStatus(token);
      if (status == null) return mcpErrorResult('Invalid Worker token');
      final sessionId = status.sessionId;
      final pending = sessionId == null
          ? null
          : await DispatchPendingStore().read(sessionId);
      return mcpJsonResult({
        ...status.toJson(),
        if (pending != null) 'pending': pending.toJson(),
      });
    },
  );

  server.registerTool(
    'dispatch_record_validation_results',
    description:
        'Worker-private tool: record verification results. Mark the session validated when all pass, or failed when any result fails.',
    inputSchema: JsonSchema.object(
      properties: {
        'workerToken': JsonSchema.string(),
        'sessionId': JsonSchema.string(),
        'results': JsonSchema.array(
          items: JsonSchema.object(
            properties: {
              'commandSummary': JsonSchema.string(),
              'executable': JsonSchema.string(),
              'args': JsonSchema.array(items: JsonSchema.string()),
              'cwd': JsonSchema.string(),
              'exitCode': JsonSchema.number(),
              'durationMs': JsonSchema.number(),
              'timedOut': JsonSchema.boolean(),
              'output': JsonSchema.string(),
            },
            required: [
              'commandSummary',
              'executable',
              'args',
              'cwd',
              'exitCode',
              'durationMs',
              'timedOut',
            ],
          ),
        ),
      },
      required: ['workerToken', 'sessionId', 'results'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final token = mcpTrimmedString(args['workerToken']);
      final sessionId = mcpTrimmedString(args['sessionId']);
      if (token == null || sessionId == null) {
        return mcpErrorResult('workerToken and sessionId cannot be empty');
      }
      final results = _parseValidationResults(args['results']);
      if (results == null) {
        return mcpErrorResult('results has an invalid format');
      }
      return _recordValidation(controller, token, sessionId, results);
    },
  );

  server.registerTool(
    'dispatch_finalize',
    description:
        'Worker-private tool: idempotently commit Git changes and move the card to Verify.',
    inputSchema: JsonSchema.object(
      properties: {
        'workerToken': JsonSchema.string(),
        'sessionId': JsonSchema.string(),
      },
      required: ['workerToken', 'sessionId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final token = mcpTrimmedString(args['workerToken']);
      final sessionId = mcpTrimmedString(args['sessionId']);
      if (token == null || sessionId == null) {
        return mcpErrorResult('workerToken and sessionId cannot be empty');
      }
      return dispatchFinalize(
        controller,
        workerToken: token,
        sessionId: sessionId,
      );
    },
  );

  for (final toolName in const [
    'dispatch_fail_agent_session',
    'dispatch_block_agent_session',
    'dispatch_skip_agent_session',
  ]) {
    server.registerTool(
      toolName,
      description:
          'Worker-private tool: record a failure and optionally move this round\'s card to Blocked.',
      inputSchema: JsonSchema.object(
        properties: {
          'workerToken': JsonSchema.string(),
          'sessionId': JsonSchema.string(),
          'reason': JsonSchema.string(),
        },
        required: ['workerToken', 'sessionId'],
      ),
      annotations: const ToolAnnotations(
        readOnlyHint: false,
        destructiveHint: false,
        openWorldHint: false,
      ),
      callback: (args, extra) async {
        final token = mcpTrimmedString(args['workerToken']);
        final sessionId = mcpTrimmedString(args['sessionId']);
        if (token == null || sessionId == null) {
          return mcpErrorResult('workerToken and sessionId cannot be empty');
        }
        return dispatchFailOrBlock(
          controller,
          workerToken: token,
          sessionId: sessionId,
          reason:
              mcpTrimmedString(args['reason']) ?? 'Worker ended this session',
          block: toolName != 'dispatch_fail_agent_session',
        );
      },
    );
  }

  server.registerTool(
    'dispatch_report_shell_span',
    description:
        'Worker-private tool: report Shell start/end events so ready_to_submit can reject unfinished tests.',
    inputSchema: JsonSchema.object(
      properties: {
        'workerToken': JsonSchema.string(),
        'sessionId': JsonSchema.string(),
        'callId': JsonSchema.string(),
        'command': JsonSchema.string(),
        'phase': JsonSchema.string(description: 'start or end'),
        'startedAtMs': JsonSchema.number(),
        'endedAtMs': JsonSchema.number(),
        'executionTimeMs': JsonSchema.number(),
        'exitCode': JsonSchema.number(),
      },
      required: ['workerToken', 'callId', 'command', 'phase'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) {
      final token = mcpFirstString(args, const ['workerToken', 'worker_token']);
      final callId = normalizeDispatchCallId(
        mcpFirstString(args, const ['callId', 'call_id']),
      );
      final command = mcpFirstString(args, const ['command', 'cmd']) ?? '';
      final phase = mcpFirstString(args, const ['phase'])?.toLowerCase();
      final missing = [
        if (token == null) 'workerToken',
        if (callId.isEmpty) 'callId',
        if (phase == null) 'phase',
      ];
      if (token == null || callId.isEmpty || phase == null) {
        final keys = args.keys.join(',');
        return Future.value(
          mcpErrorResult(
            '${missing.join(', ')} cannot be empty'
            '${keys.isEmpty ? '' : ' (received fields: $keys)'}',
          ),
        );
      }
      return dispatchReportShellSpan(
        workerToken: token,
        sessionId: mcpFirstString(args, const ['sessionId', 'session_id']),
        callId: callId,
        command: command,
        phase: phase,
        startedAtMs: (args['startedAtMs'] as num?)?.toInt() ??
            (args['started_at_ms'] as num?)?.toInt(),
        endedAtMs: (args['endedAtMs'] as num?)?.toInt() ??
            (args['ended_at_ms'] as num?)?.toInt(),
        executionTimeMs: (args['executionTimeMs'] as num?)?.toInt() ??
            (args['execution_time_ms'] as num?)?.toInt(),
        exitCode: (args['exitCode'] as num?)?.toInt() ??
            (args['exit_code'] as num?)?.toInt(),
      );
    },
  );

  server.registerTool(
    'dispatch_close_agent_session',
    description:
        'Worker-private tool: close this round\'s temporary MCP endpoint.',
    inputSchema: JsonSchema.object(
      properties: {'workerToken': JsonSchema.string()},
      required: ['workerToken'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final token = mcpTrimmedString(args['workerToken']);
      if (token == null) return mcpErrorResult('workerToken cannot be empty');
      final sessionId = McpDispatchCardGate.instance.sessionIdForToken(token);
      if (closeScopedEndpoint != null) await closeScopedEndpoint(token);
      McpDispatchCardGate.instance.closeAgentSession(token);
      if (sessionId != null) {
        DispatchShellSpanStore.instance.clearSession(sessionId);
      }
      return mcpJsonResult({'ok': true});
    },
  );
}

List<DispatchValidationResult>? _parseValidationResults(dynamic raw) {
  if (raw is! List) return null;
  final results = <DispatchValidationResult>[];
  for (final item in raw) {
    if (item is! Map) return null;
    final commandSummary = mcpTrimmedString(item['commandSummary']);
    final executable = mcpTrimmedString(item['executable']);
    final args = item['args'];
    final cwd = mcpTrimmedString(item['cwd']);
    final exitCode = item['exitCode'];
    final durationMs = item['durationMs'];
    final timedOut = item['timedOut'];
    if (commandSummary == null ||
        executable == null ||
        args is! List ||
        args.any((value) => value is! String) ||
        cwd == null ||
        exitCode is! num ||
        durationMs is! num ||
        timedOut is! bool) {
      return null;
    }
    results.add(DispatchValidationResult(
      commandSummary: commandSummary,
      executable: executable,
      args: args.cast<String>().toList(growable: false),
      cwd: cwd,
      exitCode: exitCode.toInt(),
      durationMs: durationMs.toInt(),
      timedOut: timedOut,
      output: mcpTrimmedString(item['output']),
    ));
  }
  return results;
}

Future<CallToolResult> _recordValidation(
  BoardController controller,
  String workerToken,
  String sessionId,
  List<DispatchValidationResult> results,
) async {
  final store = DispatchPendingStore();
  final record = await store.read(sessionId);
  if (record == null ||
      !McpDispatchCardGate.instance.authorizesPending(
        workerToken: workerToken,
        projectId: record.projectId,
        repoPath: record.repoPath,
      )) {
    return mcpErrorResult('No pending session was found for this Worker');
  }
  if (record.status == DispatchPendingStatus.validated) {
    return mcpJsonResult(record.toJson());
  }
  if (record.status != DispatchPendingStatus.declared) {
    return mcpErrorResult(
      'Verification results cannot be recorded in status ${record.status.name}',
    );
  }
  final shapeError = dispatchValidationShapeError(
    isManual: record.manualVerificationReason != null,
    results: results,
  );
  if (shapeError != null) return mcpErrorResult(shapeError);
  DispatchValidationResult? failed;
  for (var index = 0; index < results.length; index++) {
    final result = results[index];
    final expected = record.verificationCommands[index];
    if (result.timedOut || result.exitCode != expected.expectedExitCode) {
      failed = result;
      break;
    }
  }
  final next = record.copyWith(
    status: failed == null
        ? DispatchPendingStatus.validated
        : DispatchPendingStatus.failed,
    validationResults: results,
    error: failed == null
        ? null
        : failed.timedOut
            ? 'Verification command timed out: ${failed.commandSummary}'
            : 'Verification command failed (exitCode=${failed.exitCode}): '
                '${failed.commandSummary}',
    clearError: failed == null,
  );
  await store.write(next);
  final cardTitle = await controller.runOnProject(
    record.projectId,
    () async => controller.findCardById(record.cardId)?.title ?? record.cardId,
  );
  final totalDurationMs =
      results.fold<int>(0, (total, result) => total + result.durationMs);
  await controller.recordActivity(
    projectId: record.projectId,
    entityId: record.cardId,
    entityTitle: cardTitle,
    action: ActivityAction.updated,
    source: ActivitySource.mcp,
    details: {
      'validationMode':
          record.manualVerificationReason == null ? 'session' : 'manual',
      'commandCount': '${record.verificationCommands.length}',
      'totalDurationMs': '$totalDurationMs',
      if (record.manualVerificationReason != null)
        'manualReason': _truncate(record.manualVerificationReason!),
      'resultSummary': _truncate(
        failed == null
            ? (record.manualVerificationReason == null
                ? 'Verified in session'
                : 'Manual verification')
            : failed.timedOut
                ? 'Verification timed out: ${failed.commandSummary}'
                : 'Verification failed: ${failed.commandSummary}, exitCode=${failed.exitCode}',
      ),
    },
  );
  return mcpJsonResult(next.toJson());
}

String _truncate(String value) =>
    value.length <= 500 ? value : '${value.substring(0, 499)}…';
