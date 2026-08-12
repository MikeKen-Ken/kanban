import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../kanban/move_to_rework_on_new_feedback.dart';
import '../views/card_reference.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_block_card.dart';
import 'mcp_card_payloads.dart';
import 'mcp_set_card_commit_ref.dart';
import 'mcp_submit_for_verify.dart';
import 'mcp_tool_results.dart';

/// 注册卡片读写、移动与完成相关 MCP 工具。
void registerKanbanMcpCardTools(McpServer server, BoardController controller) {
  server.registerTool(
    'get_card',
    description: '按 cardId 获取单张卡片详情（含关联、外链等）',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'projectId': JsonSchema.string(description: '可选，缩小查找范围'),
      },
      required: ['cardId'],
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      if (cardId.isEmpty) return mcpErrorResult('cardId 不能为空');
      final projectId = mcpTrimmedString(args['projectId']);
      final refs = await controller.loadAllCardReferences();
      CardReference? match;
      for (final card in refs) {
        if (card.cardId != cardId) continue;
        if (projectId != null && card.projectId != projectId) continue;
        match = card;
        break;
      }
      if (match == null) return mcpErrorResult('未找到卡片：$cardId');
      return mcpJsonResult(mcpCardDetails(match));
    },
  );

  server.registerTool(
    'create_card',
    description:
        '在指定列创建卡片；支持到期日、提醒、重复、标签、清单、验证反馈、关联与外链。'
        '多项目时必须传 projectId（默认列 id 跨项目相同）',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(description: '标题'),
        'columnId': JsonSchema.string(description: '列 id'),
        'projectId': JsonSchema.string(
          description: '项目 id；多项目时必填，单项目可省略',
        ),
        'description': JsonSchema.string(description: '备注'),
        'priority': JsonSchema.string(
          description: 'none | low | medium | high',
        ),
        'dueDate': JsonSchema.string(description: 'ISO8601 或 epoch 毫秒'),
        'reminderAt': JsonSchema.string(description: 'ISO8601 或 epoch 毫秒'),
        'recurrence': JsonSchema.string(
          description: 'none | daily | weekly | monthly',
        ),
        'labels': JsonSchema.array(
          items: JsonSchema.string(description: '标签 key'),
        ),
        'checklist': JsonSchema.array(
          items: JsonSchema.object(properties: {
            'text': JsonSchema.string(),
            'completed': JsonSchema.boolean(),
          }),
          description: '字符串数组或 {text,completed} 对象数组',
        ),
        'verificationFeedback': JsonSchema.array(
          items: JsonSchema.object(properties: {
            'text': JsonSchema.string(),
            'completed': JsonSchema.boolean(),
          }),
          description: '验证反馈；格式同 checklist',
        ),
        'blockedByIds': JsonSchema.array(
          items: JsonSchema.string(description: '阻塞本卡的卡片 id'),
        ),
        'relatedIds': JsonSchema.array(
          items: JsonSchema.string(description: '相关卡片 id'),
        ),
        'links': JsonSchema.array(
          items: JsonSchema.object(properties: {
            'url': JsonSchema.string(description: '外链 URL'),
            'title': JsonSchema.string(description: '显示标题'),
            'id': JsonSchema.string(description: '可选，省略则自动生成'),
          }),
          description: '外链；也可用 URL 字符串数组',
        ),
        'colorValue': JsonSchema.number(description: '卡片背景色 ARGB'),
      },
      required: ['title', 'columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final title = mcpTrimmedString(args['title']) ?? '';
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      if (title.isEmpty) return mcpErrorResult('title 不能为空');
      if (columnId.isEmpty) return mcpErrorResult('columnId 不能为空');

      return runMcpForProject(
        controller,
        args['projectId'] as String?,
        (projectId) async {
        final due = parseMcpEpoch(args['dueDate'], fieldName: 'dueDate');
        if (due.hasError) return mcpErrorResult(due.error!);
        final reminder =
            parseMcpEpoch(args['reminderAt'], fieldName: 'reminderAt');
        if (reminder.hasError) return mcpErrorResult(reminder.error!);

        final labels = (args['labels'] as List?)
                ?.whereType<String>()
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList() ??
            const <String>[];
        final checklist = parseMcpChecklist(args['checklist']);
        final verificationFeedback =
            parseMcpChecklist(args['verificationFeedback']);
        final blockedByIds = parseMcpIdList(args['blockedByIds']);
        final relatedIds = parseMcpIdList(args['relatedIds']);
        final links = parseMcpLinks(args['links']);
        final description = mcpTrimmedString(args['description']);
        final recurrence = args['recurrence'] == null
            ? CardRecurrence.none
            : parseMcpRecurrence(args['recurrence'] as String?);
        final colorValue = (args['colorValue'] as num?)?.toInt();

        final cardId = await controller.addCard(
          columnId,
          title,
          description: description,
          dueDate: due.value,
          reminderAt: reminder.value,
          recurrence: recurrence,
          priority: parseMcpPriority(args['priority'] as String?),
          labels: labels,
        );
        if (cardId == null) {
          return mcpErrorResult('创建失败：请确认项目与列 id 有效');
        }

        if (checklist != null ||
            verificationFeedback != null ||
            colorValue != null ||
            blockedByIds != null ||
            relatedIds != null ||
            links != null) {
          final updateError = await controller.updateCardFull(
            columnId,
            cardId,
            checklist: checklist,
            verificationFeedback: verificationFeedback,
            blockedByIds: blockedByIds,
            relatedIds: relatedIds,
            links: links,
            colorValue: colorValue,
          );
          if (updateError != null) return mcpErrorResult(updateError);
        }

        final actualColumnId =
            controller.findColumnIdForCard(cardId) ?? columnId;
        return mcpJsonResult({
          'cardId': cardId,
          'projectId': projectId,
          'columnId': actualColumnId,
          'title': title,
        });
      },
        requireExplicitWhenMultiple: true,
      );
    },
  );

  server.registerTool(
    'update_card',
    description:
        '更新卡片字段（需提供所在列）；支持到期日、提醒、重复、标签、清单、验证反馈、关联、外链与颜色。'
        '省略 projectId 时按 cardId 定位所属项目，不依赖当前激活项目',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(),
        'columnId': JsonSchema.string(),
        'projectId': JsonSchema.string(
          description: '目标项目；省略则按 cardId 跨项目定位',
        ),
        'title': JsonSchema.string(),
        'description': JsonSchema.string(),
        'priority': JsonSchema.string(),
        'completed': JsonSchema.boolean(),
        'dueDate': JsonSchema.string(description: 'ISO8601 或 epoch 毫秒'),
        'clearDueDate': JsonSchema.boolean(),
        'reminderAt': JsonSchema.string(description: 'ISO8601 或 epoch 毫秒'),
        'clearReminder': JsonSchema.boolean(),
        'recurrence': JsonSchema.string(),
        'labels': JsonSchema.array(items: JsonSchema.string()),
        'checklist': JsonSchema.array(
          items: JsonSchema.object(properties: {
            'text': JsonSchema.string(),
            'completed': JsonSchema.boolean(),
          }),
        ),
        'verificationFeedback': JsonSchema.array(
          items: JsonSchema.object(properties: {
            'text': JsonSchema.string(),
            'completed': JsonSchema.boolean(),
          }),
          description: '验证反馈整表替换；传空数组清空；格式同 checklist',
        ),
        'blockedByIds': JsonSchema.array(
          items: JsonSchema.string(description: '阻塞本卡的卡片 id；传空数组清空'),
        ),
        'relatedIds': JsonSchema.array(
          items: JsonSchema.string(description: '相关卡片 id；传空数组清空'),
        ),
        'links': JsonSchema.array(
          items: JsonSchema.object(properties: {
            'url': JsonSchema.string(description: '外链 URL'),
            'title': JsonSchema.string(description: '显示标题'),
            'id': JsonSchema.string(description: '可选，省略则自动生成'),
          }),
          description: '外链整表替换；传空数组清空；也可用 URL 字符串数组',
        ),
        'colorValue': JsonSchema.number(),
        'clearColor': JsonSchema.boolean(),
        'commitRef': JsonSchema.string(
          description: '完成该任务对应的 Git 提交号（完整或短 hash）',
        ),
        'clearCommitRef': JsonSchema.boolean(),
      },
      required: ['cardId', 'columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      if (cardId.isEmpty || columnId.isEmpty) {
        return mcpErrorResult('cardId 与 columnId 均不能为空');
      }
      final located = await resolveMcpProjectIdForCard(
        controller,
        cardId: cardId,
        projectId: args['projectId'] as String?,
        expectedColumnId: columnId,
      );
      if (located.error != null) return located.error!;
      return runMcpForProject(controller, located.projectId,
          (projectId) async {
        final due = parseMcpEpoch(args['dueDate'], fieldName: 'dueDate');
        if (due.hasError) return mcpErrorResult(due.error!);
        final reminder =
            parseMcpEpoch(args['reminderAt'], fieldName: 'reminderAt');
        if (reminder.hasError) return mcpErrorResult(reminder.error!);

        final labels = args.containsKey('labels')
            ? (parseMcpIdList(args['labels']) ?? const <String>[])
            : null;
        final checklist = args.containsKey('checklist')
            ? (parseMcpChecklist(args['checklist']) ?? const <ChecklistItem>[])
            : null;
        final verificationFeedback = args.containsKey('verificationFeedback')
            ? (parseMcpChecklist(args['verificationFeedback']) ??
                const <ChecklistItem>[])
            : null;
        final blockedByIds = args.containsKey('blockedByIds')
            ? (parseMcpIdList(args['blockedByIds']) ?? const <String>[])
            : null;
        final relatedIds = args.containsKey('relatedIds')
            ? (parseMcpIdList(args['relatedIds']) ?? const <String>[])
            : null;
        final links = args.containsKey('links')
            ? (parseMcpLinks(args['links']) ?? const <CardLink>[])
            : null;

        final updateError = await controller.updateCardFull(
          columnId,
          cardId,
          title: mcpTrimmedString(args['title']),
          description: (args['description'] as String?)?.trim(),
          clearDescription: args.containsKey('description') &&
              ((args['description'] as String?)?.trim().isEmpty ?? true),
          priority: args['priority'] == null
              ? null
              : parseMcpPriority(args['priority'] as String?),
          completed: args['completed'] as bool?,
          dueDate: due.value,
          clearDueDate: args['clearDueDate'] == true,
          reminderAt: reminder.value,
          clearReminder: args['clearReminder'] == true,
          recurrence: args['recurrence'] == null
              ? null
              : parseMcpRecurrence(args['recurrence'] as String?),
          labels: labels,
          checklist: checklist,
          verificationFeedback: verificationFeedback,
          blockedByIds: blockedByIds,
          relatedIds: relatedIds,
          links: links,
          colorValue: (args['colorValue'] as num?)?.toInt(),
          clearColor: args['clearColor'] == true,
          commitRef: args.containsKey('commitRef')
              ? mcpTrimmedString(args['commitRef'])
              : null,
          clearCommitRef: args['clearCommitRef'] == true ||
              (args.containsKey('commitRef') &&
                  (mcpTrimmedString(args['commitRef'])?.isEmpty ?? true)),
        );
        if (updateError != null) return mcpErrorResult(updateError);
        final actualColumnId =
            controller.findColumnIdForCard(cardId) ?? columnId;
        return mcpJsonResult({
          'ok': true,
          'cardId': cardId,
          'columnId': actualColumnId,
          'projectId': projectId,
        });
      });
    },
  );

  server.registerTool(
    'move_card',
    description:
        '将卡片移动到另一列（可改显示位置）。'
        '待返工列仍有未完成验证反馈时不可离开；'
        '其他列有未完成验证反馈时不可移入已完成列（列名可自定义，默认「已完成」）。'
        '省略 projectId 时按 cardId 定位所属项目，不依赖当前激活项目',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(),
        'fromColumnId': JsonSchema.string(),
        'toColumnId': JsonSchema.string(),
        'projectId': JsonSchema.string(
          description: '目标项目；省略则按 cardId 跨项目定位',
        ),
        'toIndex': JsonSchema.number(description: '目标列显示下标，默认末尾'),
      },
      required: ['cardId', 'fromColumnId', 'toColumnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      final fromColumnId = mcpTrimmedString(args['fromColumnId']) ?? '';
      final toColumnId = mcpTrimmedString(args['toColumnId']) ?? '';
      if (cardId.isEmpty || fromColumnId.isEmpty || toColumnId.isEmpty) {
        return mcpErrorResult('cardId / fromColumnId / toColumnId 不能为空');
      }
      final located = await resolveMcpProjectIdForCard(
        controller,
        cardId: cardId,
        projectId: args['projectId'] as String?,
        expectedColumnId: fromColumnId,
      );
      if (located.error != null) return located.error!;
      return runMcpForProject(controller, located.projectId,
          (projectId) async {
        final board = controller.board;
        if (board == null) return mcpErrorResult('看板未就绪');
        final toColumn = board.columns.cast<KanbanColumn?>().firstWhere(
              (column) => column!.id == toColumnId,
              orElse: () => null,
            );
        if (toColumn == null) return mcpErrorResult('目标列不存在：$toColumnId');

        final toIndex =
            (args['toIndex'] as num?)?.toInt() ?? toColumn.cards.length;
        final moveError = await controller.moveCard(
          cardId: cardId,
          fromColumnId: fromColumnId,
          toColumnId: toColumnId,
          toDisplayIndex: toIndex.clamp(0, toColumn.cards.length),
        );
        if (moveError != null) return mcpErrorResult(moveError);
        return mcpJsonResult({
          'ok': true,
          'cardId': cardId,
          'toColumnId': toColumnId,
          'projectId': projectId,
        });
      });
    },
  );

  server.registerTool(
    'submit_card_for_verify',
    description:
        '将卡片移入「待验证」（实施成功收尾）。只需 cardId 即可：有未完成验证反馈时默认全部勾完成再移列。'
        '可选 completeAllIncompleteFeedback / completedFeedbackIds / verificationFeedback（三选一）。'
        '成功时返回 suggestedCommitMessage（直接用作 git commit 信息）。'
        '实施失败请改用 block_card。'
        '省略 projectId 时按 cardId 定位所属项目',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'projectId': JsonSchema.string(
          description: '目标项目；省略则按 cardId 跨项目定位',
        ),
        'completeAllIncompleteFeedback': JsonSchema.boolean(
          description:
              '可选；true=勾选全部未完成反馈。省略且仅传 cardId 时：有未完成反馈则默认勾全选',
        ),
        'verificationFeedback': JsonSchema.array(
          items: JsonSchema.object(properties: {
            'id': JsonSchema.string(),
            'text': JsonSchema.string(),
            'completed': JsonSchema.boolean(),
          }),
          description: '可选；移列前整表替换验证反馈（与另两种反馈参数互斥）',
        ),
        'completedFeedbackIds': JsonSchema.array(
          items: JsonSchema.string(),
          description: '可选；只勾选指定验证反馈 id（与另两种反馈参数互斥）',
        ),
      },
      required: ['cardId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      if (cardId.isEmpty) return mcpErrorResult('cardId 不能为空');
      final verificationFeedback = args.containsKey('verificationFeedback')
          ? parseMcpChecklist(args['verificationFeedback'])
          : null;
      if (args.containsKey('verificationFeedback') &&
          verificationFeedback == null) {
        return mcpErrorResult('verificationFeedback 格式无效');
      }
      final completedFeedbackIds = args.containsKey('completedFeedbackIds')
          ? parseMcpIdList(args['completedFeedbackIds'])
          : null;
      if (args.containsKey('completedFeedbackIds') &&
          completedFeedbackIds == null) {
        return mcpErrorResult('completedFeedbackIds 格式无效');
      }
      final completeAllRaw = args['completeAllIncompleteFeedback'];
      final bool? completeAll = completeAllRaw is bool ? completeAllRaw : null;
      return mcpSubmitCardForVerify(
        controller,
        cardId: cardId,
        projectId: args['projectId'] as String?,
        verificationFeedback: verificationFeedback,
        completedFeedbackIds: completedFeedbackIds,
        completeAllIncompleteFeedback: completeAll,
      );
    },
  );

  server.registerTool(
    'block_card',
    description:
        '将卡片移入「阻塞中」。实施失败或无法继续时使用；只需 cardId。'
        '省略 projectId 时按 cardId 定位所属项目',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'projectId': JsonSchema.string(
          description: '目标项目；省略则按 cardId 跨项目定位',
        ),
      },
      required: ['cardId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      if (cardId.isEmpty) return mcpErrorResult('cardId 不能为空');
      return mcpBlockCard(
        controller,
        cardId: cardId,
        projectId: args['projectId'] as String?,
      );
    },
  );

  server.registerTool(
    'complete_card',
    description:
        '将卡片标记为完成（会按项目设置移入已完成列）。'
        '仍有未完成验证反馈时拒绝。'
        '省略 projectId 时按 cardId 定位所属项目',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(),
        'columnId': JsonSchema.string(),
        'projectId': JsonSchema.string(
          description: '目标项目；省略则按 cardId 跨项目定位',
        ),
      },
      required: ['cardId', 'columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      if (cardId.isEmpty || columnId.isEmpty) {
        return mcpErrorResult('cardId 与 columnId 均不能为空');
      }
      final located = await resolveMcpProjectIdForCard(
        controller,
        cardId: cardId,
        projectId: args['projectId'] as String?,
        expectedColumnId: columnId,
      );
      if (located.error != null) return located.error!;
      return runMcpForProject(controller, located.projectId,
          (projectId) async {
        final board = controller.board;
        if (board == null) return mcpErrorResult('看板未就绪');
        KanbanCard? target;
        for (final column in board.columns) {
          if (column.id != columnId) continue;
          for (final card in column.cards) {
            if (card.id == cardId) {
              target = card;
              break;
            }
          }
        }
        if (target == null) return mcpErrorResult('卡片不存在');
        if (hasIncompleteVerificationFeedback(target.verificationFeedback)) {
          return mcpErrorResult(
            incompleteVerificationFeedbackBlocksProgressMessage,
          );
        }
        if (!target.completed) {
          final completionError =
              await controller.toggleCardCompleted(columnId, cardId);
          if (completionError != null) {
            return mcpErrorResult(completionError);
          }
        }
        return mcpJsonResult({
          'ok': true,
          'cardId': cardId,
          'completed': true,
          'projectId': projectId,
        });
      });
    },
  );

  server.registerTool(
    'set_card_commit_ref',
    description:
        '写入卡片「提交号」（Git commit hash，完整或短均可）。'
        '只需 cardId 与 commitRef；省略 projectId 时按 cardId 跨项目定位。'
        '传 clearCommitRef=true 可清除。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'commitRef': JsonSchema.string(
          description: 'Git 提交号；与 clearCommitRef 二选一',
        ),
        'clearCommitRef': JsonSchema.boolean(
          description: 'true 时清除已有提交号',
        ),
        'projectId': JsonSchema.string(
          description: '目标项目；省略则按 cardId 跨项目定位',
        ),
      },
      required: ['cardId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      if (cardId.isEmpty) return mcpErrorResult('cardId 不能为空');
      return mcpSetCardCommitRef(
        controller,
        cardId: cardId,
        projectId: args['projectId'] as String?,
        commitRef: args['commitRef'] as String?,
        clearCommitRef: args['clearCommitRef'] == true,
      );
    },
  );

  server.registerTool(
    'delete_card',
    description:
        '删除卡片（进入回收站）。省略 projectId 时按 cardId 定位所属项目',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(),
        'columnId': JsonSchema.string(),
        'projectId': JsonSchema.string(
          description: '目标项目；省略则按 cardId 跨项目定位',
        ),
      },
      required: ['cardId', 'columnId'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']) ?? '';
      final columnId = mcpTrimmedString(args['columnId']) ?? '';
      if (cardId.isEmpty || columnId.isEmpty) {
        return mcpErrorResult('cardId 与 columnId 均不能为空');
      }
      final located = await resolveMcpProjectIdForCard(
        controller,
        cardId: cardId,
        projectId: args['projectId'] as String?,
        expectedColumnId: columnId,
      );
      if (located.error != null) return located.error!;
      return runMcpForProject(controller, located.projectId,
          (projectId) async {
        await controller.deleteCard(columnId, cardId);
        return mcpJsonResult({
          'ok': true,
          'cardId': cardId,
          'projectId': projectId,
        });
      });
    },
  );
}
