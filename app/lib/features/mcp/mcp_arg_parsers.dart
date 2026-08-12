import 'package:mcp_dart/mcp_dart.dart';
import 'package:uuid/uuid.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../activity/activity_models.dart';
import '../kanban/kanban_labels.dart';
import '../views/filter_spec.dart';
import 'mcp_card_payloads.dart';
import 'mcp_tool_results.dart';

/// 解析优先级字符串；未知值回退为 none。
CardPriority parseMcpPriority(String? raw) {
  final value = (raw ?? 'none').trim().toLowerCase();
  return CardPriority.values.firstWhere(
    (item) => item.name == value,
    orElse: () => CardPriority.none,
  );
}

/// 解析重复规则；未知值回退为 none。
CardRecurrence parseMcpRecurrence(String? raw) {
  return CardRecurrence.fromString(raw);
}

/// 日期解析结果：epoch 毫秒或错误文案。
class McpEpochParse {
  const McpEpochParse({this.value, this.error});

  final int? value;
  final String? error;

  bool get hasError => error != null;
}

/// 将 ISO8601 字符串或 epoch 毫秒解析为毫秒时间戳。
McpEpochParse parseMcpEpoch(Object? raw, {required String fieldName}) {
  if (raw == null) return const McpEpochParse();
  if (raw is num) return McpEpochParse(value: raw.toInt());
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const McpEpochParse();
    final asInt = int.tryParse(trimmed);
    if (asInt != null) return McpEpochParse(value: asInt);
    final dt = DateTime.tryParse(trimmed);
    if (dt != null) {
      return McpEpochParse(value: dt.millisecondsSinceEpoch);
    }
    return McpEpochParse(error: '$fieldName 无法解析：$trimmed');
  }
  return McpEpochParse(error: '$fieldName 类型无效');
}

/// 从 MCP 参数解析清单；支持字符串数组或 `{text, completed}` 对象数组。
List<ChecklistItem>? parseMcpChecklist(Object? raw) {
  if (raw == null) return null;
  if (raw is! List) return null;
  final items = <ChecklistItem>[];
  for (final entry in raw) {
    if (entry is String) {
      final text = entry.trim();
      if (text.isEmpty) continue;
      items.add(ChecklistItem(id: const Uuid().v4(), text: text));
      continue;
    }
    if (entry is Map) {
      final map = Map<String, dynamic>.from(entry);
      final text = (map['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;
      final id = (map['id'] as String?)?.trim();
      items.add(
        ChecklistItem(
          id: (id == null || id.isEmpty) ? const Uuid().v4() : id,
          text: text,
          completed: map['completed'] == true,
        ),
      );
    }
  }
  return items;
}

/// 解析非空字符串 id 列表；[raw] 为 null 时返回 null（表示未传该字段）。
List<String>? parseMcpIdList(Object? raw) {
  if (raw == null) return null;
  if (raw is! List) return const [];
  return raw
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

/// 从 MCP 参数解析外链；支持 URL 字符串或 `{url, title?, id?}` 对象。
///
/// [raw] 为 null 时返回 null（表示未传该字段）；空数组表示清空。
List<CardLink>? parseMcpLinks(Object? raw) {
  if (raw == null) return null;
  if (raw is! List) return const [];
  final now = DateTime.now().millisecondsSinceEpoch;
  final links = <CardLink>[];
  for (var i = 0; i < raw.length; i++) {
    final entry = raw[i];
    if (entry is String) {
      final url = entry.trim();
      if (url.isEmpty) continue;
      links.add(
        CardLink(
          id: const Uuid().v4(),
          url: url,
          order: i,
          createdAt: now,
        ),
      );
      continue;
    }
    if (entry is Map) {
      final map = Map<String, dynamic>.from(entry);
      final url = (map['url'] as String?)?.trim() ?? '';
      if (url.isEmpty) continue;
      final id = (map['id'] as String?)?.trim();
      final title = (map['title'] as String?)?.trim() ?? '';
      links.add(
        CardLink(
          id: (id == null || id.isEmpty) ? const Uuid().v4() : id,
          url: url,
          title: title,
          order: (map['order'] as num?)?.toInt() ?? i,
          createdAt: (map['createdAt'] as num?)?.toInt() ?? now,
        ),
      );
    }
  }
  return links;
}

List<String> _readStringList(Object? value) {
  if (value is String) return value.isEmpty ? const [] : [value];
  if (value is! List) return const [];
  return value.whereType<String>().where((item) => item.isNotEmpty).toList();
}

CompletionFilter _parseCompletion(Object? raw, {CompletionFilter? fallback}) {
  if (raw is bool) {
    return raw ? CompletionFilter.completed : CompletionFilter.incomplete;
  }
  final text = (raw as String?)?.trim().toLowerCase();
  if (text == null || text.isEmpty) {
    return fallback ?? CompletionFilter.any;
  }
  return switch (text) {
    'completed' || 'done' || 'true' => CompletionFilter.completed,
    'incomplete' || 'open' || 'false' => CompletionFilter.incomplete,
    'any' || 'all' => CompletionFilter.any,
    _ => CompletionFilter.fromJson(text),
  };
}

/// 从扁平 MCP 参数或嵌套 `filter` 对象构建 [FilterSpec]。
///
/// 兼容旧字段：`projectId`、`completed`；默认 completion 可由 [defaultCompletion] 指定。
FilterSpec parseMcpFilterSpec(
  Map<String, dynamic> args, {
  CompletionFilter defaultCompletion = CompletionFilter.any,
}) {
  final nested = args['filter'];
  final source = nested is Map
      ? <String, dynamic>{
          ...Map<String, dynamic>.from(nested),
          // 顶层字段覆盖嵌套，便于局部覆盖
          ...args,
        }
      : args;

  final projectIds = _readStringList(
    source['projectIds'] ?? source['projectId'],
  );
  final columnIds = _readStringList(
    source['columnIds'] ?? source['columnId'],
  );
  final labelIds = _readStringList(source['labelIds'] ?? source['labels']);
  final priorities = _readStringList(
    source['priorities'] ?? source['priority'],
  );

  final completionRaw = source['completion'] ?? source['completed'];
  final completion = completionRaw == null
      ? defaultCompletion
      : _parseCompletion(completionRaw, fallback: defaultCompletion);

  return FilterSpec(
    keyword: ((source['keyword'] as String?) ??
            (source['query'] as String?) ??
            '')
        .trim(),
    projectIds: projectIds,
    columnIds: columnIds,
    labelIds: labelIds,
    labelMatchMode: LabelMatchMode.fromJson(source['labelMatchMode']),
    priorities: priorities,
    completion: completion,
    dueDate: DueDateFilter.fromJson(
      source['dueDate'] ?? source['dueDateFilter'] ?? source['dateFilter'],
    ),
    sortField: CardSortField.fromJson(
      source['sortField'] ?? source['sortBy'],
    ),
    sortDirection: SortDirection.fromJson(source['sortDirection']),
  );
}

String? mcpTrimmedString(Object? value) {
  final text = (value as String?)?.trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

int mcpLimit(Object? raw, {int fallback = 30, int max = 100}) {
  return ((raw as num?)?.toInt() ?? fallback).clamp(1, max);
}

/// MCP `projectId` 参数说明：支持项目 UUID 或项目标题。
String mcpProjectIdParamDescription({
  String whenOmitted = '省略则用界面当前项目',
}) =>
    '项目 id 或项目名；$whenOmitted';

/// 将 MCP 传入的项目引用解析为项目 id：先精确匹配 id，再按标题（忽略大小写）匹配。
({String? projectId, CallToolResult? error}) resolveMcpProjectRef(
  BoardController controller,
  String projectRef,
) {
  final ref = projectRef.trim();
  if (ref.isEmpty) {
    return (projectId: null, error: mcpErrorResult('projectId 不能为空'));
  }
  for (final project in controller.projects) {
    if (project.id == ref) {
      return (projectId: project.id, error: null);
    }
  }
  final lower = ref.toLowerCase();
  final byTitle = [
    for (final project in controller.projects)
      if (project.title.trim().toLowerCase() == lower) project,
  ];
  if (byTitle.length == 1) {
    return (projectId: byTitle.first.id, error: null);
  }
  if (byTitle.length > 1) {
    final detail =
        byTitle.map((project) => '${project.title}（${project.id}）').join('、');
    return (
      projectId: null,
      error: mcpErrorResult('项目名「$ref」匹配多个项目，请改传项目 id：$detail'),
    );
  }
  return (projectId: null, error: mcpErrorResult('项目不存在：$ref'));
}

/// 可选 projectId：未传则 `projectId=null`；传入则解析为 id。
({String? projectId, CallToolResult? error}) resolveOptionalMcpProjectId(
  BoardController controller,
  String? projectId,
) {
  final explicit = mcpTrimmedString(projectId);
  if (explicit == null) return (projectId: null, error: null);
  return resolveMcpProjectRef(controller, explicit);
}

/// 若指定了项目 id/名，仅校验并可解析；不切换 UI 当前项目。
/// 项目不存在时返回错误结果；未指定时返回 null。
Future<CallToolResult?> ensureMcpProject(
  BoardController controller,
  String? projectId,
) async {
  final id = mcpTrimmedString(projectId);
  if (id == null) return null;
  return resolveMcpProjectRef(controller, id).error;
}

/// 多项目且省略 projectId 时的统一错误（默认列 id 跨项目相同）。
CallToolResult mcpMissingProjectIdError() => mcpErrorResult(
      '存在多个项目时必须显式传入 projectId（id 或项目名）'
      '（默认列 id 如 todo/doing 跨项目相同，省略会写到错误项目）',
    );

/// 解析 MCP 目标项目（省略则界面当前项目）；不切换 UI。
///
/// [projectId] 可为项目 UUID 或项目标题；先匹配 id，再按标题忽略大小写匹配。
/// 回退使用 [BoardController.uiActiveProjectId]，避免 [BoardController.runOnProject]
/// 临时切换 active 时把并发/缺省写操作绑错项目。
///
/// [requireExplicitWhenMultiple]：多项目且未传 projectId 时直接报错（用于按列 id 创建等写路径）。
({String? projectId, CallToolResult? error}) resolveMcpProjectId(
  BoardController controller,
  String? projectId, {
  bool requireExplicitWhenMultiple = false,
}) {
  final explicit = mcpTrimmedString(projectId);
  if (explicit == null &&
      requireExplicitWhenMultiple &&
      controller.projects.length > 1) {
    return (projectId: null, error: mcpMissingProjectIdError());
  }
  if (explicit != null) {
    return resolveMcpProjectRef(controller, explicit);
  }
  final id = controller.uiActiveProjectId;
  if (id == null) {
    return (projectId: null, error: mcpErrorResult('没有可用项目'));
  }
  final exists = controller.projects.any((project) => project.id == id);
  if (!exists) {
    return (projectId: null, error: mcpErrorResult('项目不存在：$id'));
  }
  return (projectId: id, error: null);
}

/// 按 cardId 定位所属项目；显式 [projectId]（id 或项目名）时校验卡片确在该项目。
///
/// 用于 update/move/complete/delete 等：省略 projectId 时不依赖「当前激活项目」，
/// 避免列 id 跨项目相同导致写错板。
Future<({String? projectId, String? columnId, CallToolResult? error})>
    resolveMcpProjectIdForCard(
  BoardController controller, {
  required String cardId,
  String? projectId,
  String? expectedColumnId,
}) async {
  final explicitRaw = mcpTrimmedString(projectId);
  String? explicitId;
  if (explicitRaw != null) {
    final resolved = resolveMcpProjectRef(controller, explicitRaw);
    if (resolved.error != null) {
      return (
        projectId: null,
        columnId: null,
        error: resolved.error,
      );
    }
    explicitId = resolved.projectId;
  }
  final expectedColumn = mcpTrimmedString(expectedColumnId);
  final refs = await controller.loadAllCardReferences();
  final matches = [
    for (final ref in refs)
      if (ref.cardId == cardId &&
          (explicitId == null || ref.projectId == explicitId))
        ref,
  ];
  if (matches.isEmpty) {
    if (explicitId != null) {
      return (
        projectId: null,
        columnId: null,
        error: mcpErrorResult('项目 $explicitId 中未找到卡片：$cardId'),
      );
    }
    return (
      projectId: null,
      columnId: null,
      error: mcpErrorResult('未找到卡片：$cardId'),
    );
  }
  if (matches.length > 1) {
    return (
      projectId: null,
      columnId: null,
      error: mcpErrorResult('卡片 $cardId 匹配多个项目，请显式传入 projectId'),
    );
  }
  final match = matches.first;
  if (expectedColumn != null && match.columnId != expectedColumn) {
    return (
      projectId: null,
      columnId: null,
      error: mcpErrorResult(
        '卡片 $cardId 不在列 $expectedColumn'
        '（实际列 ${match.columnId}，项目 ${match.projectId}）',
      ),
    );
  }
  return (projectId: match.projectId, columnId: match.columnId, error: null);
}

/// 在目标项目上下文中执行 MCP 操作（不切换 UI active 项目）。
Future<CallToolResult> runMcpForProject(
  BoardController controller,
  String? projectId,
  Future<CallToolResult> Function(String projectId) action, {
  bool requireExplicitWhenMultiple = false,
}) async {
  final resolved = resolveMcpProjectId(
    controller,
    projectId,
    requireExplicitWhenMultiple: requireExplicitWhenMultiple,
  );
  if (resolved.error != null) return resolved.error!;
  final id = resolved.projectId!;
  return controller.runOnProject(
    id,
    () => controller.runWithActivitySource(
      ActivitySource.mcp,
      () => action(id),
    ),
  );
}

/// 兼容旧调用；新列表实现统一使用 [mcpBoardCardSummary]。
Map<String, dynamic> mcpCardSummary(
  KanbanCard card, {
  int descriptionMax = 120,
}) =>
    mcpBoardCardSummary(
      card,
      includeDetails: true,
      descriptionMax: descriptionMax,
    );
