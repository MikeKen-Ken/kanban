import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_run_context_store.dart';
import 'mcp_tool_results.dart';

const _resumeStatuses = {
  'not_attempted',
  'resumed',
  'unavailable',
  'failed',
  'new_agent',
};

void registerKanbanMcpRunContextTools(
  McpServer server,
  BoardController controller, {
  McpRunContextStore? store,
}) {
  final contextStore = store ?? McpRunContextStore();

  server.registerTool(
    'get_run_context',
    description: '读取卡片的本机 agent/Git 恢复上下文；该数据不参与 WebDAV 同步。',
    inputSchema: _identitySchema,
    annotations: const ToolAnnotations(
      readOnlyHint: true,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final ids = _readIdentity(args);
      if (ids.error != null) return mcpErrorResult(ids.error!);
      return runMcpForProject(controller, ids.projectId, (projectId) async {
        if (controller.findCardById(ids.cardId!) == null) {
          return mcpErrorResult('卡片不存在：${ids.cardId}');
        }
        final context = await contextStore.read(
          projectId: projectId,
          cardId: ids.cardId!,
        );
        return mcpJsonResult({
          'found': context != null,
          if (context != null) 'context': context.toJson(),
        });
      });
    },
  );

  server.registerTool(
    'save_run_context',
    description: '保存卡片的本机 agent/Git 恢复上下文；整条替换，不修改卡片正文，也不参与 WebDAV 同步。'
        '若传 lastCommit，会同步写入卡片「提交号」字段（可 WebDAV 同步）。',
    inputSchema: JsonSchema.object(
      properties: {
        ..._identityProperties,
        'runId': JsonSchema.string(description: '当前稳定运行 id'),
        'lastSubagentId': JsonSchema.string(),
        'baseCommit': JsonSchema.string(),
        'lastCommit': JsonSchema.string(),
        'reviewRound': JsonSchema.number(description: '非负整数'),
        'handoffSummary': JsonSchema.string(description: '简短交接摘要，最多 8000 字符'),
        'resumeStatus': JsonSchema.string(
          description:
              'not_attempted | resumed | unavailable | failed | new_agent',
        ),
      },
      required: ['projectId', 'cardId', 'runId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final ids = _readIdentity(args);
      if (ids.error != null) return mcpErrorResult(ids.error!);
      final runId = mcpTrimmedString(args['runId']);
      if (runId == null) return mcpErrorResult('runId 不能为空');
      final reviewRound = (args['reviewRound'] as num?)?.toInt() ?? 0;
      if (reviewRound < 0) return mcpErrorResult('reviewRound 不能小于 0');
      final handoffSummary = mcpTrimmedString(args['handoffSummary']);
      if ((handoffSummary?.length ?? 0) > 8000) {
        return mcpErrorResult('handoffSummary 不能超过 8000 字符');
      }
      final resumeStatus =
          mcpTrimmedString(args['resumeStatus']) ?? 'not_attempted';
      if (!_resumeStatuses.contains(resumeStatus)) {
        return mcpErrorResult('resumeStatus 无效：$resumeStatus');
      }
      return runMcpForProject(controller, ids.projectId, (projectId) async {
        if (controller.findCardById(ids.cardId!) == null) {
          return mcpErrorResult('卡片不存在：${ids.cardId}');
        }
        final context = McpRunContext(
          projectId: projectId,
          cardId: ids.cardId!,
          runId: runId,
          lastSubagentId: mcpTrimmedString(args['lastSubagentId']),
          baseCommit: mcpTrimmedString(args['baseCommit']),
          lastCommit: mcpTrimmedString(args['lastCommit']),
          reviewRound: reviewRound,
          handoffSummary: handoffSummary,
          resumeStatus: resumeStatus,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await contextStore.write(context);
        final lastCommit = context.lastCommit;
        if (lastCommit != null && lastCommit.isNotEmpty) {
          final columnId = controller.findColumnIdForCard(ids.cardId!);
          if (columnId != null) {
            await controller.updateCardFull(
              columnId,
              ids.cardId!,
              commitRef: lastCommit,
            );
          }
        }
        return mcpJsonResult({'ok': true, 'context': context.toJson()});
      });
    },
  );

  server.registerTool(
    'delete_run_context',
    description: '删除卡片的本机 agent/Git 恢复上下文；不修改看板卡片。',
    inputSchema: _identitySchema,
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final ids = _readIdentity(args);
      if (ids.error != null) return mcpErrorResult(ids.error!);
      return runMcpForProject(controller, ids.projectId, (projectId) async {
        await contextStore.delete(projectId: projectId, cardId: ids.cardId!);
        return mcpJsonResult({
          'ok': true,
          'projectId': projectId,
          'cardId': ids.cardId,
        });
      });
    },
  );
}

Map<String, JsonSchema> get _identityProperties => {
      'projectId': JsonSchema.string(description: '目标项目 id；必填'),
      'cardId': JsonSchema.string(description: '目标卡片 id'),
    };

JsonObject get _identitySchema => JsonSchema.object(
      properties: _identityProperties,
      required: ['projectId', 'cardId'],
    );

({String? projectId, String? cardId, String? error}) _readIdentity(
  Map<String, dynamic> args,
) {
  final projectId = mcpTrimmedString(args['projectId']);
  final cardId = mcpTrimmedString(args['cardId']);
  if (projectId == null || cardId == null) {
    return (
      projectId: projectId,
      cardId: cardId,
      error: 'projectId / cardId 均不能为空',
    );
  }
  return (projectId: projectId, cardId: cardId, error: null);
}
