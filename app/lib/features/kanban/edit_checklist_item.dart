import '../../models/kanban_models.dart';

/// 用户明确点击「取消」且文本非空时弹出，表示丢弃编辑。
const checklistItemEditCancelled = Object();

/// 统一编辑对话框各种关闭方式的返回值。
///
/// - [checklistItemEditCancelled]：明确取消 → 丢弃编辑
/// - 非空 [String]：保存/删除（空字符串表示删除）
/// - `null`（点击遮罩或系统返回）：保存当前输入；若已清空则删除
String? resolveChecklistItemDialogResult({
  required Object? dialogResult,
  required String draftText,
}) {
  if (identical(dialogResult, checklistItemEditCancelled)) return null;
  if (dialogResult is String) return dialogResult;
  final trimmed = draftText.trim();
  return trimmed.isEmpty ? '' : trimmed;
}

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
