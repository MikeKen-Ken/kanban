import 'dart:async';

import 'package:flutter/material.dart';

import '../common/app_snack_bar.dart';
import '../controllers/board_controller.dart';
import 'webdav_sync_service.dart';

enum SyncManualAction { upload, download, merge }

/// 弹出上传 / 下载 / 合并；上传与下载会再确认。
Future<void> showSyncActionsAndRun(
  BuildContext context,
  BoardController controller,
) async {
  if (controller.syncStatus == SyncStatus.syncing) {
    showAppSnackBar(context, message: '正在同步…可点取消按钮');
    return;
  }
  if (!controller.webDavConfig.enabled ||
      !controller.webDavConfig.isConfigured) {
    showAppSnackBar(context, message: '请先在设置中配置 WebDAV');
    return;
  }

  final action = await showModalBottomSheet<SyncManualAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('上传'),
            subtitle: const Text('用本机数据全量覆盖云端'),
            onTap: () => Navigator.pop(ctx, SyncManualAction.upload),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('下载'),
            subtitle: const Text('用云端数据全量覆盖本机'),
            onTap: () => Navigator.pop(ctx, SyncManualAction.download),
          ),
          ListTile(
            leading: const Icon(Icons.sync_alt),
            title: const Text('合并'),
            subtitle: const Text('三路合并本机与云端，有差异再回写云端'),
            onTap: () => Navigator.pop(ctx, SyncManualAction.merge),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case SyncManualAction.upload:
      final confirmed = await _confirmSyncOverwrite(
        context,
        title: '上传并覆盖云端？',
        body: '云端现有看板数据将被本机数据全部覆盖，且无法自动撤销。确定继续吗？',
        confirmLabel: '覆盖云端',
      );
      if (confirmed != true || !context.mounted) return;
      unawaited(controller.uploadNow());
      return;
    case SyncManualAction.download:
      final confirmed = await _confirmSyncOverwrite(
        context,
        title: '下载并覆盖本机？',
        body: '本机现有看板数据将被云端数据全部替换，未同步的本地修改会丢失。确定继续吗？',
        confirmLabel: '覆盖本机',
      );
      if (confirmed != true || !context.mounted) return;
      unawaited(controller.downloadNow());
      return;
    case SyncManualAction.merge:
      unawaited(controller.mergeNow());
  }
}

Future<bool?> _confirmSyncOverwrite(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
