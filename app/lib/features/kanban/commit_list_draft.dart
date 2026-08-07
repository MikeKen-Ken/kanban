import '../../models/kanban_models.dart';

/// 将输入框中未点「+」的非空草稿追加为新清单项。
///
/// 空白（含仅空白字符）草稿忽略，返回原 [items] 引用。
/// 子任务与验证反馈共用同一套规则，由调用方分别传入各自列表与草稿。
List<ChecklistItem> commitChecklistDraft({
  required List<ChecklistItem> items,
  required String draftText,
  required String Function() newId,
}) {
  final text = draftText.trim();
  if (text.isEmpty) return items;
  return [
    ...items,
    ChecklistItem(id: newId(), text: text),
  ];
}
