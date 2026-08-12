import '../../common/date_utils.dart';
import 'card_reference.dart';
import 'filter_spec.dart';

/// 对跨项目卡片引用执行纯内存查询。
class CardQueryService {
  const CardQueryService();

  List<CardReference> query(
    Iterable<CardReference> cards,
    FilterSpec spec, {
    DateTime? now,
  }) {
    final queryTime = now ?? DateTime.now();
    final result =
        cards.where((card) => _matches(card, spec, queryTime)).toList();
    result.sort((left, right) => _compare(left, right, spec));
    return List.unmodifiable(result);
  }

  bool _matches(CardReference card, FilterSpec spec, DateTime now) {
    if (!_matchesKeyword(card, spec.keyword)) return false;
    if (spec.projectIds.isNotEmpty &&
        !spec.projectIds.contains(card.projectId)) {
      return false;
    }
    if (spec.columnIds.isNotEmpty && !spec.columnIds.contains(card.columnId)) {
      return false;
    }
    if (spec.priorities.isNotEmpty &&
        !spec.priorities.contains(card.priority)) {
      return false;
    }
    if (!_matchesLabels(card.labelIds, spec)) return false;
    if (!_matchesCompletion(card.completed, spec.completion)) return false;
    return _matchesDueDate(card.dueDate, spec.dueDate, now);
  }

  bool _matchesKeyword(CardReference card, String keyword) {
    final terms = keyword
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty);
    if (terms.isEmpty) return true;

    final fields = <String>[
      card.title,
      card.description ?? '',
      card.projectName,
      card.columnName,
      card.commitRef ?? '',
      ...card.labelIds,
      ...card.labelNames,
      ...card.checklistTexts,
      ...card.verificationFeedbackTexts,
      ...card.attachmentFileNames,
      for (final link in card.links) ...[
        if (link['title'] is String) link['title'] as String,
        if (link['url'] is String) link['url'] as String,
      ],
    ].map((value) => value.toLowerCase()).toList();
    return terms.every(
      (term) => fields.any((field) => field.contains(term)),
    );
  }

  bool _matchesLabels(List<String> cardLabels, FilterSpec spec) {
    if (spec.labelIds.isEmpty) return true;
    final labels = cardLabels.toSet();
    return switch (spec.labelMatchMode) {
      LabelMatchMode.any => spec.labelIds.any(labels.contains),
      LabelMatchMode.all => spec.labelIds.every(labels.contains),
    };
  }

  bool _matchesCompletion(bool completed, CompletionFilter filter) {
    return switch (filter) {
      CompletionFilter.any => true,
      CompletionFilter.incomplete => !completed,
      CompletionFilter.completed => completed,
    };
  }

  bool _matchesDueDate(
    int? dueDate,
    DueDateFilter filter,
    DateTime now,
  ) {
    if (filter == DueDateFilter.any) return true;
    if (dueDate == null) return false;
    return switch (filter) {
      DueDateFilter.any => true,
      DueDateFilter.today => isDueToday(dueDate, now),
      DueDateFilter.overdue => isOverdue(dueDate, now),
      DueDateFilter.thisWeek => isDueThisWeek(dueDate, now),
    };
  }

  int _compare(
    CardReference left,
    CardReference right,
    FilterSpec spec,
  ) {
    if (spec.sortField == CardSortField.dueDate) {
      final dueResult = _compareDueDate(left.dueDate, right.dueDate);
      if (dueResult != 0) {
        if (left.dueDate == null || right.dueDate == null) return dueResult;
        return spec.sortDirection == SortDirection.ascending
            ? dueResult
            : -dueResult;
      }
    } else {
      final primary = _compareField(left, right, spec.sortField);
      if (primary != 0) {
        return spec.sortDirection == SortDirection.ascending
            ? primary
            : -primary;
      }
    }
    return _compareIdentity(left, right);
  }

  int _compareField(
    CardReference left,
    CardReference right,
    CardSortField field,
  ) {
    return switch (field) {
      CardSortField.dueDate => _compareDueDate(left.dueDate, right.dueDate),
      CardSortField.priority => _priorityWeight(left.priority)
          .compareTo(_priorityWeight(right.priority)),
      CardSortField.title => _text(left.title).compareTo(_text(right.title)),
      CardSortField.createdAt => left.createdAt.compareTo(right.createdAt),
      CardSortField.updatedAt => left.updatedAt.compareTo(right.updatedAt),
      CardSortField.project => _compareNamedLocation(
          left.projectName,
          left.projectId,
          right.projectName,
          right.projectId,
        ),
      CardSortField.column => _compareNamedLocation(
          left.columnName,
          left.columnId,
          right.columnName,
          right.columnId,
        ),
      CardSortField.manual => left.order.compareTo(right.order),
    };
  }

  int _compareDueDate(int? left, int? right) {
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }

  int _compareNamedLocation(
    String leftName,
    String leftId,
    String rightName,
    String rightId,
  ) {
    final byName = _text(leftName).compareTo(_text(rightName));
    return byName != 0 ? byName : leftId.compareTo(rightId);
  }

  int _compareIdentity(CardReference left, CardReference right) {
    var result = left.projectId.compareTo(right.projectId);
    if (result != 0) return result;
    result = left.columnId.compareTo(right.columnId);
    if (result != 0) return result;
    result = left.order.compareTo(right.order);
    if (result != 0) return result;
    return left.cardId.compareTo(right.cardId);
  }

  String _text(String value) => value.toLowerCase();

  int _priorityWeight(String priority) => switch (priority) {
        'low' => 1,
        'medium' => 2,
        'high' => 3,
        _ => 0,
      };
}
