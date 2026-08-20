import 'package:flutter/material.dart';

/// 卡片文件附件三个点菜单项（打开 / 打开所在文件夹 / 删除）。
List<PopupMenuEntry<String>> cardFileAttachmentOverflowItems({
  required bool missing,
  required ColorScheme colors,
}) {
  return [
    if (!missing)
      const PopupMenuItem(
        value: 'open',
        child: ListTile(
          leading: Icon(Icons.open_in_new_outlined),
          title: Text('打开'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (!missing)
      const PopupMenuItem(
        value: 'directory',
        child: ListTile(
          leading: Icon(Icons.folder_open_outlined),
          title: Text('打开所在文件夹'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    PopupMenuItem(
      value: 'delete',
      child: ListTile(
        leading: Icon(
          Icons.delete_outline,
          color: colors.error,
        ),
        title: Text(
          '删除文件',
          style: TextStyle(color: colors.error),
        ),
        contentPadding: EdgeInsets.zero,
      ),
    ),
  ];
}
