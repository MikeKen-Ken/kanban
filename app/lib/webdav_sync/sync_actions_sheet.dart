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
        SyncManualAction.upload => 'Upload',
        SyncManualAction.download => 'Download',
        SyncManualAction.merge => 'Merge',
        SyncManualAction.uploadWallpapers => 'Upload wallpapers',
        SyncManualAction.downloadWallpapers => 'Download wallpapers',
      };

  IconData get icon => switch (this) {
        SyncManualAction.upload => Icons.cloud_upload_outlined,
        SyncManualAction.download => Icons.cloud_download_outlined,
        SyncManualAction.merge => Icons.sync_alt,
        SyncManualAction.uploadWallpapers => Icons.wallpaper_outlined,
        SyncManualAction.downloadWallpapers => Icons.image_outlined,
      };

  String get subtitle => switch (this) {
        SyncManualAction.upload =>
          'Replace the cloud workspace archive with local data',
        SyncManualAction.download =>
          'Replace local data with the cloud workspace archive',
        SyncManualAction.merge =>
          'Three-way merge local and cloud workspaces, then write differences back to the cloud',
        SyncManualAction.uploadWallpapers =>
          'Replace the cloud wallpaper archive with the local library',
        SyncManualAction.downloadWallpapers =>
          'Replace the local wallpaper library with the cloud archive',
      };
}

const _syncActions = SyncManualAction.values;

/// 同步前通用校验；失败时已弹出提示。
bool ensureSyncActionsAvailable(
  BuildContext context,
  BoardController controller,
) {
  if (controller.syncStatus == SyncStatus.syncing) {
    showAppSnackBar(context, message: 'Syncing… click Cancel to stop');
    return false;
  }
  if (!controller.webDavConfig.enabled ||
      !controller.webDavConfig.isConfigured) {
    showAppSnackBar(context, message: 'Configure WebDAV in Settings first');
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
        title: 'Upload and replace cloud workspace?',
        body: 'Existing cloud board data will be replaced by the local workspace archive and cannot be undone automatically. Continue?',
        confirmLabel: 'Replace cloud data',
      );
      if (confirmed != true || !context.mounted) return;
      unawaited(controller.uploadNow());
      return;
    case SyncManualAction.download:
      final confirmed = await _confirmSyncOverwrite(
        context,
        title: 'Download and replace local workspace?',
        body: 'Existing local board data will be replaced by the cloud workspace archive. Unsynced local changes will be lost. Continue?',
        confirmLabel: 'Replace local data',
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
        title: 'Upload and replace cloud wallpaper library?',
        body: 'The cloud wallpaper archive will be replaced by the local wallpaper library. Continue?',
        confirmLabel: 'Replace cloud wallpapers',
      );
      if (confirmed != true || !context.mounted) return;
      unawaited(controller.uploadWallpapersNow());
      return;
    case SyncManualAction.downloadWallpapers:
      final confirmed = await _confirmSyncOverwrite(
        context,
        title: 'Download and replace local wallpaper library?',
        body: 'The local wallpaper library will be replaced by the cloud wallpaper archive. Continue?',
        confirmLabel: 'Replace local wallpapers',
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
