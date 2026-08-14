import 'dart:async';

import 'package:flutter/material.dart';

import '../common/app_snack_bar.dart';
import '../controllers/board_controller.dart';
import 'webdav_sync_service.dart';

enum SyncManualAction {
  upload,
  download,
  merge,
  uploadWallpapers,
  downloadWallpapers,
}

extension SyncManualActionUi on SyncManualAction {
  String get label => switch (this) {
        SyncManualAction.upload => '上传',
        SyncManualAction.download => '下载',
        SyncManualAction.merge => '合并',
        SyncManualAction.uploadWallpapers => '上传壁纸库',
        SyncManualAction.downloadWallpapers => '下载壁纸库',
      };

  IconData get icon => switch (this) {
        SyncManualAction.upload => Icons.cloud_upload_outlined,
        SyncManualAction.download => Icons.cloud_download_outlined,
        SyncManualAction.merge => Icons.sync_alt,
        SyncManualAction.uploadWallpapers => Icons.wallpaper_outlined,
        SyncManualAction.downloadWallpapers => Icons.image_outlined,
      };

  String get subtitle => switch (this) {
        SyncManualAction.upload => '用本机数据覆盖云端工作区压缩包',
        SyncManualAction.download => '用云端工作区压缩包覆盖本机',
        SyncManualAction.merge => '三路合并本机与云端工作区，有差异再回写云端',
        SyncManualAction.uploadWallpapers => '用本机壁纸库覆盖云端壁纸压缩包',
        SyncManualAction.downloadWallpapers => '用云端壁纸压缩包覆盖本机壁纸库',
      };
}

const _syncActions = SyncManualAction.values;

/// 同步前通用校验；失败时已弹出提示。
bool ensureSyncActionsAvailable(
  BuildContext context,
  BoardController controller,
) {
  if (controller.syncStatus == SyncStatus.syncing) {
    showAppSnackBar(context, message: '正在同步…可点取消按钮');
    return false;
  }
  if (!controller.webDavConfig.enabled ||
      !controller.webDavConfig.isConfigured) {
    showAppSnackBar(context, message: '请先在设置中配置 WebDAV');
    return false;
  }
  return true;
}

List<PopupMenuEntry<SyncManualAction>> syncActionPopupMenuItems() {
  return [
    for (final action in _syncActions)
      PopupMenuItem<SyncManualAction>(
        value: action,
        child: ListTile(
          leading: Icon(action.icon),
          title: Text(action.label),
          subtitle: Text(action.subtitle),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ),
  ];
}

/// 在指定锚点附近弹出上传 / 下载 / 合并菜单。
Future<void> showSyncActionsMenu(
  BuildContext context,
  BoardController controller, {
  required RelativeRect position,
}) async {
  if (!ensureSyncActionsAvailable(context, controller)) return;

  final action = await showMenu<SyncManualAction>(
    context: context,
    position: position,
    items: syncActionPopupMenuItems(),
  );
  if (action == null || !context.mounted) return;
  await runSyncManualAction(context, controller, action);
}

/// 弹出上传 / 下载 / 合并；上传与下载会再确认。
Future<void> showSyncActionsAndRun(
  BuildContext context,
  BoardController controller,
) async {
  final size = MediaQuery.sizeOf(context);
  await showSyncActionsMenu(
    context,
    controller,
    position: RelativeRect.fromLTRB(
      size.width - 280,
      kToolbarHeight + 8,
      16,
      0,
    ),
  );
}

Future<void> runSyncManualAction(
  BuildContext context,
  BoardController controller,
  SyncManualAction action,
) async {
  if (!ensureSyncActionsAvailable(context, controller)) return;

  switch (action) {
    case SyncManualAction.upload:
      final confirmed = await _confirmSyncOverwrite(
        context,
        title: '上传并覆盖云端工作区？',
        body: '云端现有看板数据将被本机工作区压缩包覆盖，且无法自动撤销。确定继续吗？',
        confirmLabel: '覆盖云端',
      );
      if (confirmed != true || !context.mounted) return;
      unawaited(controller.uploadNow());
      return;
    case SyncManualAction.download:
      final confirmed = await _confirmSyncOverwrite(
        context,
        title: '下载并覆盖本机工作区？',
        body: '本机现有看板数据将被云端工作区压缩包替换，未同步的本地修改会丢失。确定继续吗？',
        confirmLabel: '覆盖本机',
      );
      if (confirmed != true || !context.mounted) return;
      unawaited(controller.downloadNow());
      return;
    case SyncManualAction.merge:
      unawaited(controller.mergeNow());
      return;
    case SyncManualAction.uploadWallpapers:
      final confirmed = await _confirmSyncOverwrite(
        context,
        title: '上传并覆盖云端壁纸库？',
        body: '云端壁纸压缩包将被本机壁纸库覆盖。确定继续吗？',
        confirmLabel: '覆盖云端壁纸',
      );
      if (confirmed != true || !context.mounted) return;
      unawaited(controller.uploadWallpapersNow());
      return;
    case SyncManualAction.downloadWallpapers:
      final confirmed = await _confirmSyncOverwrite(
        context,
        title: '下载并覆盖本机壁纸库？',
        body: '本机壁纸库将被云端壁纸压缩包替换。确定继续吗？',
        confirmLabel: '覆盖本机壁纸',
      );
      if (confirmed != true || !context.mounted) return;
      unawaited(controller.downloadWallpapersNow());
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
