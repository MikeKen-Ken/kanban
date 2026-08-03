/// 标签列表中多个值的匹配方式。
enum LabelMatchMode {
  any,
  all;

  static LabelMatchMode fromJson(Object? value) {
    return value == 'all' ? LabelMatchMode.all : LabelMatchMode.any;
  }
}

/// 卡片完成状态筛选。
enum CompletionFilter {
  any,
  incomplete,
  completed;

  static CompletionFilter fromJson(Object? value) {
    final name = value?.toString();
    return CompletionFilter.values.firstWhere(
      (item) => item.name == name,
      orElse: () => CompletionFilter.any,
    );
  }
}

/// 卡片到期日期筛选。
enum DueDateFilter {
  any,
  today,
  overdue,
  thisWeek;

  static DueDateFilter fromJson(Object? value) {
    final name = value?.toString();
    return DueDateFilter.values.firstWhere(
      (item) => item.name == name,
      orElse: () => DueDateFilter.any,
    );
  }
}

/// 查询结果排序字段。
enum CardSortField {
  dueDate,
  priority,
  title,
  createdAt,
  updatedAt,
  project,
  column,
  manual;

  static CardSortField fromJson(Object? value) {
    final name = value?.toString();
    return CardSortField.values.firstWhere(
      (item) => item.name == name,
      orElse: () => CardSortField.dueDate,
    );
  }
}

/// 查询结果排序方向。
enum SortDirection {
  ascending,
  descending;

  static SortDirection fromJson(Object? value) {
    final name = value?.toString();
    if (name == 'desc') return SortDirection.descending;
    if (name == 'asc') return SortDirection.ascending;
    return SortDirection.values.firstWhere(
      (item) => item.name == name,
      orElse: () => SortDirection.ascending,
    );
  }
}

/// 可序列化的组合筛选条件。
///
/// 同一维度内采用“或”匹配，不同维度之间采用“且”匹配。
class FilterSpec {
  const FilterSpec({
    this.keyword = '',
    this.projectIds = const [],
    this.columnIds = const [],
    this.labelIds = const [],
    this.labelMatchMode = LabelMatchMode.any,
    this.priorities = const [],
    this.completion = CompletionFilter.any,
    this.dueDate = DueDateFilter.any,
    this.sortField = CardSortField.dueDate,
    this.sortDirection = SortDirection.ascending,
  });

  final String keyword;
  final List<String> projectIds;
  final List<String> columnIds;
  final List<String> labelIds;
  final LabelMatchMode labelMatchMode;

  /// 优先级使用稳定字符串标识，避免查询模块依赖界面层类型。
  final List<String> priorities;
  final CompletionFilter completion;
  final DueDateFilter dueDate;
  final CardSortField sortField;
  final SortDirection sortDirection;

  bool get hasFilters =>
      keyword.trim().isNotEmpty ||
      projectIds.isNotEmpty ||
      columnIds.isNotEmpty ||
      labelIds.isNotEmpty ||
      priorities.isNotEmpty ||
      completion != CompletionFilter.any ||
      dueDate != DueDateFilter.any;

  FilterSpec copyWith({
    String? keyword,
    List<String>? projectIds,
    List<String>? columnIds,
    List<String>? labelIds,
    LabelMatchMode? labelMatchMode,
    List<String>? priorities,
    CompletionFilter? completion,
    DueDateFilter? dueDate,
    CardSortField? sortField,
    SortDirection? sortDirection,
  }) {
    return FilterSpec(
      keyword: keyword ?? this.keyword,
      projectIds: projectIds ?? this.projectIds,
      columnIds: columnIds ?? this.columnIds,
      labelIds: labelIds ?? this.labelIds,
      labelMatchMode: labelMatchMode ?? this.labelMatchMode,
      priorities: priorities ?? this.priorities,
      completion: completion ?? this.completion,
      dueDate: dueDate ?? this.dueDate,
      sortField: sortField ?? this.sortField,
      sortDirection: sortDirection ?? this.sortDirection,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        if (keyword.isNotEmpty) 'keyword': keyword,
        if (projectIds.isNotEmpty) 'projectIds': projectIds,
        if (columnIds.isNotEmpty) 'columnIds': columnIds,
        if (labelIds.isNotEmpty) 'labelIds': labelIds,
        if (labelIds.isNotEmpty) 'labelMatchMode': labelMatchMode.name,
        if (priorities.isNotEmpty) 'priorities': priorities,
        if (completion != CompletionFilter.any) 'completion': completion.name,
        if (dueDate != DueDateFilter.any) 'dueDate': dueDate.name,
        'sortField': sortField.name,
        'sortDirection': sortDirection.name,
      };

  /// 缺失字段使用安全默认值，并兼容早期单值及旧排序字段。
  factory FilterSpec.fromJson(Map<String, dynamic> json) {
    final sort = json['sort'];
    final sortMap = sort is Map ? sort : const <String, dynamic>{};
    final completed = json['completed'];

    return FilterSpec(
      keyword: _readString(json['keyword'] ?? json['query']),
      projectIds: _readStringList(json['projectIds'] ?? json['projectId']),
      columnIds: _readStringList(json['columnIds'] ?? json['columnId']),
      labelIds: _readStringList(json['labelIds'] ?? json['labels']),
      labelMatchMode: LabelMatchMode.fromJson(
          json['labelMatchMode'] ?? json['matchLabels']),
      priorities: _readStringList(json['priorities'] ?? json['priority']),
      completion: completed is bool
          ? (completed
              ? CompletionFilter.completed
              : CompletionFilter.incomplete)
          : CompletionFilter.fromJson(
              json['completion'] ?? json['completionStatus'],
            ),
      dueDate: _readDueDateFilter(json),
      sortField: CardSortField.fromJson(
        json['sortField'] ?? json['sortBy'] ?? sortMap['field'],
      ),
      sortDirection: _readSortDirection(json, sortMap),
    );
  }
}

DueDateFilter _readDueDateFilter(Map<String, dynamic> json) {
  final explicit =
      json['dueDate'] ?? json['dueDateFilter'] ?? json['dateFilter'];
  if (explicit != null) return DueDateFilter.fromJson(explicit);
  if (json['dueToday'] == true) return DueDateFilter.today;
  if (json['overdue'] == true) return DueDateFilter.overdue;
  if (json['dueThisWeek'] == true) return DueDateFilter.thisWeek;
  return DueDateFilter.any;
}

SortDirection _readSortDirection(
  Map<String, dynamic> json,
  Map<dynamic, dynamic> sort,
) {
  final ascending = json['ascending'];
  if (ascending is bool) {
    return ascending ? SortDirection.ascending : SortDirection.descending;
  }
  return SortDirection.fromJson(
    json['sortDirection'] ?? sort['direction'],
  );
}

String _readString(Object? value) => value is String ? value : '';

List<String> _readStringList(Object? value) {
  if (value is String) return value.isEmpty ? const [] : [value];
  if (value is! List) return const [];
  return value.whereType<String>().where((item) => item.isNotEmpty).toList();
}
