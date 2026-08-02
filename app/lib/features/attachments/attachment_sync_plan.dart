/// JSON 工作区已与远端一致时，是否仍需补传本地附件。
///
/// 旧逻辑在 JSON 相等时直接跳过 push，导致「看板已引用、本地有文件、远端缺失」
/// 的附件永远不会被补传，其它端下载会一直 404。
bool shouldReconcileAttachmentsWhenJsonEquals({
  required bool jsonEquals,
  required bool attachmentSyncAvailable,
}) {
  return jsonEquals && attachmentSyncAvailable;
}

/// 本地有文件且远端尚无对应文件时需要上传。
bool shouldUploadAttachmentFile({
  required bool localExists,
  required bool remoteExists,
}) {
  return localExists && !remoteExists;
}
