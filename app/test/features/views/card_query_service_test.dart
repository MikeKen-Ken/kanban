import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/views/views.dart';

void main() {
  const service = CardQueryService();
  final now = DateTime(2026, 8, 5, 12);
  final cards = [
    _card(
      id: 'c1',
      projectId: 'work',
      projectName: '工作',
      columnId: 'doing',
      columnName: '进行中',
      title: '发布 Android 版本',
      description: '检查商店资料',
      labels: ['release', 'urgent'],
      labelNames: ['发布', '紧急'],
      checklist: ['生成安装包'],
      priority: 'high',
      dueDate: DateTime(2026, 8, 5, 18),
      updatedAt: 30,
      order: 2,
    ),
    _card(
      id: 'c2',
      projectId: 'work',
      projectName: '工作',
      columnId: 'todo',
      columnName: '待办',
      title: '整理需求',
      labels: ['planning'],
      priority: 'low',
      dueDate: DateTime(2026, 8, 4, 18),
      updatedAt: 10,
      order: 1,
    ),
    _card(
      id: 'c3',
      projectId: 'home',
      projectName: '家庭',
      columnId: 'todo',
      columnName: '待办',
      title: '购买灯泡',
      labels: ['urgent', 'shopping'],
      priority: 'medium',
      dueDate: DateTime(2026, 8, 9, 18),
      completed: true,
      updatedAt: 20,
    ),
    _card(
      id: 'c4',
      projectId: 'home',
      projectName: '家庭',
      columnId: 'later',
      columnName: '以后',
      title: '无日期任务',
      updatedAt: 40,
    ),
  ];

  test('可按项目和列筛选跨项目引用', () {
    final result = service.query(
      cards,
      const FilterSpec(projectIds: ['work'], columnIds: ['todo']),
      now: now,
    );

    expect(result.map((card) => card.cardId), ['c2']);
    expect(result.single.projectName, '工作');
    expect(result.single.columnName, '待办');
  });

  test('关键词不区分大小写并覆盖描述、标签名和清单', () {
    expect(
      service
          .query(cards, const FilterSpec(keyword: 'ANDROID 商店'), now: now)
          .map((card) => card.cardId),
      ['c1'],
    );
    expect(
      service
          .query(cards, const FilterSpec(keyword: '紧急 安装包'), now: now)
          .map((card) => card.cardId),
      ['c1'],
    );
  });

  test('关键词覆盖提交号、验证反馈与附件名', () {
    final extended = [
      ...cards,
      _card(
        id: 'c5',
        title: '部署',
        commitRef: 'abc1234',
        verificationFeedback: ['按钮未对齐'],
        attachmentFileNames: ['验证截图.png'],
      ),
    ];

    expect(
      service
          .query(extended, const FilterSpec(keyword: 'abc1234'), now: now)
          .map((card) => card.cardId),
      ['c5'],
    );
    expect(
      service
          .query(extended, const FilterSpec(keyword: '按钮未对齐'), now: now)
          .map((card) => card.cardId),
      ['c5'],
    );
    expect(
      service
          .query(extended, const FilterSpec(keyword: '验证截图'), now: now)
          .map((card) => card.cardId),
      ['c5'],
    );
  });

  test('标签支持任一和全部匹配', () {
    final any = service.query(
      cards,
      const FilterSpec(labelIds: ['release', 'shopping']),
      now: now,
    );
    final all = service.query(
      cards,
      const FilterSpec(
        labelIds: ['urgent', 'shopping'],
        labelMatchMode: LabelMatchMode.all,
      ),
      now: now,
    );

    expect(any.map((card) => card.cardId), ['c1', 'c3']);
    expect(all.map((card) => card.cardId), ['c3']);
  });

  test('优先级和完成状态组合采用且匹配', () {
    final result = service.query(
      cards,
      const FilterSpec(
        priorities: ['high', 'medium'],
        completion: CompletionFilter.incomplete,
      ),
      now: now,
    );

    expect(result.map((card) => card.cardId), ['c1']);
  });

  test('全局视图可组合项目、状态和排序条件', () {
    final result = service.query(
      cards,
      const FilterSpec(
        projectIds: ['work', 'home'],
        completion: CompletionFilter.incomplete,
        sortField: CardSortField.updatedAt,
        sortDirection: SortDirection.descending,
      ),
      now: now,
    );

    expect(result.map((card) => card.cardId), ['c4', 'c1', 'c2']);
  });

  test('今日筛选只包含今天到期的卡片', () {
    final result = service.query(
      cards,
      const FilterSpec(dueDate: DueDateFilter.today),
      now: now,
    );

    expect(result.map((card) => card.cardId), ['c1']);
  });

  test('逾期筛选不包含今天及无日期卡片', () {
    final result = service.query(
      cards,
      const FilterSpec(dueDate: DueDateFilter.overdue),
      now: now,
    );

    expect(result.map((card) => card.cardId), ['c2']);
  });

  test('本周筛选覆盖周一到周日', () {
    final result = service.query(
      cards,
      const FilterSpec(dueDate: DueDateFilter.thisWeek),
      now: now,
    );

    expect(result.map((card) => card.cardId), ['c2', 'c1', 'c3']);
  });

  test('到期日升降序都将无日期卡片放在末尾', () {
    final ascending = service.query(cards, const FilterSpec(), now: now);
    final descending = service.query(
      cards,
      const FilterSpec(sortDirection: SortDirection.descending),
      now: now,
    );

    expect(ascending.map((card) => card.cardId), ['c2', 'c1', 'c3', 'c4']);
    expect(descending.map((card) => card.cardId), ['c3', 'c1', 'c2', 'c4']);
  });

  test('优先级可按高到低排序', () {
    final result = service.query(
      cards,
      const FilterSpec(
        sortField: CardSortField.priority,
        sortDirection: SortDirection.descending,
      ),
      now: now,
    );

    expect(result.map((card) => card.cardId), ['c1', 'c3', 'c2', 'c4']);
  });

  test('更新时间排序并以引用身份提供确定性顺序', () {
    final result = service.query(
      [
        _card(id: 'b', projectId: 'p', updatedAt: 1),
        _card(id: 'a', projectId: 'p', updatedAt: 1),
        _card(id: 'c', projectId: 'p', updatedAt: 2),
      ],
      const FilterSpec(sortField: CardSortField.updatedAt),
      now: now,
    );

    expect(result.map((card) => card.cardId), ['a', 'b', 'c']);
  });

  test('查询结果不可修改且保留调用方原始对象', () {
    final source = Object();
    final result = service.query(
      [_card(id: 'source', source: source)],
      const FilterSpec(),
      now: now,
    );

    expect(identical(result.single.source, source), isTrue);
    expect(
      () => result.add(_card(id: 'other')),
      throwsUnsupportedError,
    );
  });
}

CardReference _card({
  required String id,
  String projectId = 'project',
  String projectName = '',
  String columnId = 'column',
  String columnName = '',
  String title = '任务',
  String? description,
  List<String> labels = const [],
  List<String> labelNames = const [],
  List<String> checklist = const [],
  List<String> verificationFeedback = const [],
  List<String> attachmentFileNames = const [],
  String? commitRef,
  String priority = 'none',
  bool completed = false,
  DateTime? dueDate,
  int updatedAt = 0,
  int order = 0,
  Object? source,
}) {
  return CardReference(
    projectId: projectId,
    projectName: projectName,
    columnId: columnId,
    columnName: columnName,
    cardId: id,
    title: title,
    description: description,
    labelIds: labels,
    labelNames: labelNames,
    checklistTexts: checklist,
    verificationFeedbackTexts: verificationFeedback,
    attachmentFileNames: attachmentFileNames,
    commitRef: commitRef,
    priority: priority,
    completed: completed,
    dueDate: dueDate?.millisecondsSinceEpoch,
    createdAt: 1,
    updatedAt: updatedAt,
    order: order,
    source: source,
  );
}
