import '../../models/kanban_models.dart';

/// 根据编辑对话框结果更新清单项列表（子任务 / 验证反馈共用）。
///
/// [dialogResult] 约定：
/// - `null`：取消且文本非空 → 丢弃编辑，返回原 [items] 引用
/// - 空字符串：清空后点保存或取消 → 删除对应 id 的项
/// - 非空字符串：保存为该项的新文本
List<ChecklistItem> applyChecklistItemEdit({
  required List<ChecklistItem> items,
  required String id,
  required String? dialogResult,
}) {
  if (dialogResult == null) return items;
  if (dialogResult.isEmpty) {
    return items.where((item) => item.id != id).toList();
  }
  return [
    for (final item in items)
      if (item.id == id) item.copyWith(text: dialogResult) else item,
  ];
}
