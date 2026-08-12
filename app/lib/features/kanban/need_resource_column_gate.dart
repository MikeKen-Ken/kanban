import '../../models/kanban_models.dart';
import 'verify_column.dart';

/// 预置「缺资源」标签 key（与主题预置一致）。
const needResourceLabelKey = 'need_resource';

/// 带有「缺资源」标签时，卡片只能留在「阻塞中」列。
const needResourceMustStayInBlockedMessage = '带有「缺资源」标签的卡片只能留在阻塞中列';

/// [labels] 是否含「缺资源」。
bool cardHasNeedResourceLabel(Iterable<String> labels) =>
    labels.contains(needResourceLabelKey);

/// 跨列移卡门禁：带「缺资源」时目标列必须是「阻塞中」。
///
/// 同列内重排不校验。无该标签时不拦截。
String? needResourceMoveRejectionReason({
  required String fromColumnId,
  required String toColumnId,
  required Iterable<String> labels,
  required Iterable<KanbanColumn> columns,
}) {
  if (fromColumnId == toColumnId) return null;
  if (!cardHasNeedResourceLabel(labels)) return null;
  if (isBlockedColumnId(columnId: toColumnId, columns: columns)) return null;
  return needResourceMustStayInBlockedMessage;
}

/// 带「缺资源」且当前不在阻塞中时，返回应移入的列 id；否则 `null`。
String? targetBlockedColumnIdIfNeedResource({
  required Iterable<String> labels,
  required String currentColumnId,
  required Iterable<KanbanColumn> columns,
}) {
  if (!cardHasNeedResourceLabel(labels)) return null;
  final blocked = findBlockedColumn(columns);
  if (blocked == null || blocked.id == currentColumnId) return null;
  return blocked.id;
}

/// 创建/落位时：有「缺资源」则落到阻塞中列，否则保留 [preferredColumnId]。
String resolveColumnIdForNeedResourceLabels({
  required String preferredColumnId,
  required Iterable<String> labels,
  required Iterable<KanbanColumn> columns,
}) {
  if (!cardHasNeedResourceLabel(labels)) return preferredColumnId;
  final blocked = findBlockedColumn(columns);
  return blocked?.id ?? preferredColumnId;
}
