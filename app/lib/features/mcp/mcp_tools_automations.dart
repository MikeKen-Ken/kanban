import 'package:mcp_dart/mcp_dart.dart';
import 'package:uuid/uuid.dart';

import '../../controllers/board_controller.dart';
import '../automations/automation_models.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

AutomationTrigger? _parseTrigger(String raw) {
  final lower = raw.toLowerCase();
  for (final trigger in AutomationTrigger.values) {
    if (trigger.name.toLowerCase() == lower) return trigger;
  }
  return null;
}

AutomationActionType? _parseAction(String raw) {
  final lower = raw.toLowerCase();
  for (final action in AutomationActionType.values) {
    if (action.name.toLowerCase() == lower) return action;
  }
  return null;
}

/// 注册自动化规则相关 MCP 工具。
void registerKanbanMcpAutomationTools(
  McpServer server,
  BoardController controller,
) {
  server.registerTool(
    'list_automation_rules',
    description: '列出当前项目（或指定项目）的自动化规则',
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(description: '省略则用当前项目'),
      },
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final resolved =
          resolveMcpProjectId(controller, args['projectId'] as String?);
      if (resolved.error != null) return resolved.error!;
      final projectId = resolved.projectId!;
      final settings = await controller.loadProjectSettingsSnapshot(projectId);
      if (settings == null) {
        return mcpErrorResult('项目不存在或未加载：$projectId');
      }
      final rules = settings.automationRules;
      return mcpJsonResult({
        'projectId': projectId,
        'count': rules.length,
        'rules': [for (final rule in rules) rule.toJson()],
      });
    },
  );

  server.registerTool(
    'upsert_automation_rule',
    description:
        '新建或更新自动化规则。触发：movedToColumn | completed | checklistAllDone | overdue；'
        '动作：markCompleted | moveToDoneColumn | setPriority | addLabel | clearReminder',
    inputSchema: JsonSchema.object(
      properties: {
        'projectId': JsonSchema.string(),
        'id': JsonSchema.string(description: '已有规则 id；省略则新建'),
        'name': JsonSchema.string(description: '规则名称'),
        'enabled': JsonSchema.boolean(description: '默认 true'),
        'trigger': JsonSchema.string(
          description:
              'movedToColumn | completed | checklistAllDone | overdue',
        ),
        'triggerColumnId': JsonSchema.string(
          description: 'trigger=movedToColumn 时的目标列 id',
        ),
        'action': JsonSchema.string(
          description:
              'markCompleted | moveToDoneColumn | setPriority | addLabel | clearReminder',
        ),
        'actionPriority': JsonSchema.string(
          description: 'action=setPriority 时：none | low | medium | high',
        ),
        'actionLabelKey': JsonSchema.string(
          description: 'action=addLabel 时的标签 key',
        ),
      },
      required: ['name', 'trigger', 'action'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      return runMcpForProject(controller, args['projectId'] as String?,
          (projectId) async {
        final name = mcpTrimmedString(args['name']) ?? '';
        if (name.isEmpty) return mcpErrorResult('name 不能为空');

        final triggerRaw = mcpTrimmedString(args['trigger']);
        if (triggerRaw == null) return mcpErrorResult('trigger 不能为空');
        final trigger = _parseTrigger(triggerRaw);
        if (trigger == null) {
          return mcpErrorResult(
            'trigger 无效：$triggerRaw（可用 movedToColumn | completed | checklistAllDone | overdue）',
          );
        }

        final actionRaw = mcpTrimmedString(args['action']);
        if (actionRaw == null) return mcpErrorResult('action 不能为空');
        final action = _parseAction(actionRaw);
        if (action == null) {
          return mcpErrorResult(
            'action 无效：$actionRaw（可用 markCompleted | moveToDoneColumn | setPriority | addLabel | clearReminder）',
          );
        }

        final triggerColumnId =
            mcpTrimmedString(args['triggerColumnId']) ?? '';
        if (trigger == AutomationTrigger.movedToColumn &&
            triggerColumnId.isEmpty) {
          return mcpErrorResult('movedToColumn 触发需要 triggerColumnId');
        }

        final actionLabelKey = mcpTrimmedString(args['actionLabelKey']) ?? '';
        if (action == AutomationActionType.addLabel && actionLabelKey.isEmpty) {
          return mcpErrorResult('addLabel 动作需要 actionLabelKey');
        }

        final actionPriority =
            (mcpTrimmedString(args['actionPriority']) ?? 'high').toLowerCase();
        if (action == AutomationActionType.setPriority) {
          final allowed = {'none', 'low', 'medium', 'high'};
          if (!allowed.contains(actionPriority)) {
            return mcpErrorResult(
              'actionPriority 无效：$actionPriority（可用 none | low | medium | high）',
            );
          }
        }

        final existingId = mcpTrimmedString(args['id']);
        final rules = [...controller.projectSettings.automationRules];
        final index = existingId == null
            ? -1
            : rules.indexWhere((r) => r.id == existingId);
        if (existingId != null && index < 0) {
          return mcpErrorResult('未找到规则：$existingId');
        }

        final rule = AutomationRule(
          id: existingId ?? const Uuid().v4(),
          name: name,
          enabled: args['enabled'] as bool? ?? true,
          trigger: trigger,
          triggerColumnId: triggerColumnId,
          action: action,
          actionPriority: actionPriority,
          actionLabelKey: actionLabelKey,
        );

        if (index >= 0) {
          rules[index] = rule;
        } else {
          rules.add(rule);
        }

        await controller.saveProjectSettings(
          controller.projectSettings.copyWith(automationRules: rules),
        );
        return mcpJsonResult({
          'ok': true,
          'created': index < 0,
          'projectId': projectId,
          'rule': rule.toJson(),
        });
      });
    },
  );

  server.registerTool(
    'delete_automation_rule',
    description: '删除一条自动化规则',
    inputSchema: JsonSchema.object(
      properties: {
        'id': JsonSchema.string(description: '规则 id'),
        'projectId': JsonSchema.string(),
      },
      required: ['id'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final id = mcpTrimmedString(args['id']) ?? '';
      if (id.isEmpty) return mcpErrorResult('id 不能为空');
      return runMcpForProject(controller, args['projectId'] as String?,
          (projectId) async {
        final rules = controller.projectSettings.automationRules;
        if (!rules.any((rule) => rule.id == id)) {
          return mcpErrorResult('未找到规则：$id');
        }
        await controller.saveProjectSettings(
          controller.projectSettings.copyWith(
            automationRules: [
              for (final rule in rules)
                if (rule.id != id) rule,
            ],
          ),
        );
        return mcpJsonResult({
          'ok': true,
          'id': id,
          'projectId': projectId,
        });
      });
    },
  );
}
