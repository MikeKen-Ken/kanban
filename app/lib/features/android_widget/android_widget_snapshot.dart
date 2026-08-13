import '../../common/date_utils.dart';
import '../../models/kanban_models.dart';
import '../kanban/move_to_rework_on_new_feedback.dart';
import '../kanban/next_work_card.dart';

const androidWidgetMaxItems = 5;

/// 小组件展示的一条卡片摘要。
class AndroidWidgetCardItem {
  const AndroidWidgetCardItem({
    required this.title,
    required this.badge,
  });

  final String title;
  final String badge;

  Map<String, dynamic> toJson() => {
        'title': title,
        'badge': badge,
      };
}

/// 写入安卓小组件的快照数据。
class AndroidWidgetSnapshot {
  const AndroidWidgetSnapshot({
    required this.projectName,
    required this.updatedAt,
    required this.overdueCount,
    required this.todayCount,
    required this.todoCount,
    required this.items,
  });

  final String projectName;
  final int updatedAt;
  final int overdueCount;
  final int todayCount;
  final int todoCount;
  final List<AndroidWidgetCardItem> items;

  Map<String, dynamic> toJson() => {
        'projectName': projectName,
        'updatedAt': updatedAt,
        'overdueCount': overdueCount,
        'todayCount': todayCount,
        'todoCount': todoCount,
        'items': [for (final item in items) item.toJson()],
      };
}

int _badgePriority(String badge) => switch (badge) {
      '逾期' => 0,
      '今日' => 1,
      '返工' => 2,
      '待办' => 3,
      _ => 4,
    };

/// 根据当前项目看板生成小组件快照。
AndroidWidgetSnapshot buildAndroidWidgetSnapshot({
  required KanbanBoard board,
  required String projectName,
  DateTime? now,
  int maxItems = androidWidgetMaxItems,
}) {
  final reference = now ?? DateTime.now();
  final reworkColumn = findReworkColumn(board.columns);
  final todoColumn = findTodoColumn(board.columns);
  final reworkColumnId = reworkColumn?.id;
  final todoColumnId = todoColumn?.id;

  var overdueCount = 0;
  var todayCount = 0;
  var todoCount = 0;
  final candidates = <({
    String title,
    String badge,
    int? dueDate,
    int updatedAt,
  })>[];

  for (final column in board.columns) {
    for (final card in column.cards) {
      if (card.completed) continue;

      final dueDate = card.dueDate;
      String? badge;
      if (dueDate != null) {
        if (isOverdue(dueDate, reference)) {
          badge = '逾期';
          overdueCount++;
        } else if (isDueToday(dueDate, reference)) {
          badge = '今日';
          todayCount++;
        }
      }

      if (badge == null) {
        if (reworkColumnId != null && column.id == reworkColumnId) {
          badge = '返工';
        } else if (todoColumnId != null && column.id == todoColumnId) {
          badge = '待办';
          todoCount++;
        } else {
          continue;
        }
      }

      final title = card.title.trim();
      if (title.isEmpty) continue;
      candidates.add((
        title: title,
        badge: badge,
        dueDate: dueDate,
        updatedAt: card.updatedAt,
      ));
    }
  }

  candidates.sort((a, b) {
    final badgeCompare =
        _badgePriority(a.badge).compareTo(_badgePriority(b.badge));
    if (badgeCompare != 0) return badgeCompare;
    final aDue = a.dueDate;
    final bDue = b.dueDate;
    if (aDue != null && bDue != null) {
      final dueCompare = aDue.compareTo(bDue);
      if (dueCompare != 0) return dueCompare;
    } else if (aDue != null) {
      return -1;
    } else if (bDue != null) {
      return 1;
    }
    return b.updatedAt.compareTo(a.updatedAt);
  });

  final items = candidates
      .take(maxItems)
      .map(
        (entry) => AndroidWidgetCardItem(
          title: entry.title,
          badge: entry.badge,
        ),
      )
      .toList();

  return AndroidWidgetSnapshot(
    projectName: projectName.trim().isEmpty ? board.title : projectName.trim(),
    updatedAt: reference.millisecondsSinceEpoch,
    overdueCount: overdueCount,
    todayCount: todayCount,
    todoCount: todoCount,
    items: items,
  );
}
