import 'package:mcp_dart/mcp_dart.dart';
import 'package:uuid/uuid.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../kanban/kanban_labels.dart';
import '../views/filter_spec.dart';
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

/// 若指定了非当前项目则切换；项目不存在时返回错误结果。
Future<CallToolResult?> ensureMcpProject(
  BoardController controller,
  String? projectId,
) async {
  final id = mcpTrimmedString(projectId);
  if (id == null) return null;
  if (id == controller.activeProjectId) return null;
  final exists = controller.projects.any((project) => project.id == id);
  if (!exists) return mcpErrorResult('项目不存在：$id');
  await controller.switchProject(id);
  return null;
}

/// 卡片摘要（用于 list_board，备注截断）。
Map<String, dynamic> mcpCardSummary(
  KanbanCard card, {
  int descriptionMax = 120,
}) {
  final description = card.description;
  String? truncated;
  if (description != null && description.isNotEmpty) {
    truncated = description.length <= descriptionMax
        ? description
        : '${description.substring(0, descriptionMax)}…';
  }
  return {
    'id': card.id,
    'title': card.title,
    'completed': card.completed,
    'priority': card.priority.name,
    if (card.dueDate != null) 'dueDate': card.dueDate,
    if (card.labels.isNotEmpty) 'labels': card.labels,
    if (card.hasChecklist)
      'checklist': {
        'done': card.checklistDone,
        'total': card.checklist.length,
      },
    if (truncated != null) 'description': truncated,
    if (card.colorValue != null) 'colorValue': card.colorValue,
    if (card.attachments.isNotEmpty)
      'attachmentCount': card.attachments.length,
  };
}
