/// 关闭卡片详情时：是否应丢弃（删除）空白卡，而非保留。
///
/// 判定：有效标题与备注（trim 后）皆空，且 [hasOtherMetadata] 为 false。
/// 有效标题与详情页持久化一致：编辑框为空时回退到原标题，避免清空已有卡标题后误删。
bool shouldDiscardBlankCard({
  required String editedTitle,
  required String originalTitle,
  required String editedDescription,
  bool hasOtherMetadata = false,
}) {
  final title = editedTitle.trim().isEmpty
      ? originalTitle.trim()
      : editedTitle.trim();
  final description = editedDescription.trim();
  if (title.isNotEmpty || description.isNotEmpty) return false;
  if (hasOtherMetadata) return false;
  return true;
}
