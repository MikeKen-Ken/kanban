import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/app_snack_bar.dart';
import '../controllers/board_controller.dart';
import '../main.dart';
import 'sync_actions_sheet.dart';
import 'sync_quick_switch.dart';
import 'webdav_sync_service.dart';

/// 右上角同步操作：短按下拉菜单，长按滑动快速选择。
class SyncActionsSwitcher extends StatelessWidget {
  const SyncActionsSwitcher({
    super.key,
    required this.status,
    required this.error,
    required this.conflictCount,
    required this.lastSyncedAt,
    required this.progress,
    required this.pendingUploadCount,
    required this.compact,
    required this.onConflictTap,
    required this.onCancel,
  });

  final SyncStatus status;
  final String? error;
  final int conflictCount;
  final DateTime? lastSyncedAt;
  final SyncProgress? progress;
  final int pendingUploadCount;
  final bool compact;
  final VoidCallback onConflictTap;
  final VoidCallback? onCancel;

  static const double _menuMinWidth = 280;
  static const double _menuMaxWidth = 360;

  /// AppBar 圆形 [IconButton] 默认 48 触控区、24 图标，两侧各留 12。
  /// 同步入口不是 IconButton，补同样水平留白，避免贴回收站/设置过近。
  static const double _appBarIconButtonSideInset = 12;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<BoardController>();
    final syncing = status == SyncStatus.syncing;
    final hasConflict = conflictCount > 0;

    final Widget child;
    if (hasConflict) {
      child = _SyncStatusTrigger(
        status: status,
        error: error,
        conflictCount: conflictCount,
        lastSyncedAt: lastSyncedAt,
        progress: progress,
        pendingUploadCount: pendingUploadCount,
        compact: compact,
        showDropdownArrow: false,
        onTap: onConflictTap,
        onCancel: onCancel,
      );
    } else if (syncing) {
      child = _SyncStatusTrigger(
        status: status,
        error: error,
        conflictCount: conflictCount,
        lastSyncedAt: lastSyncedAt,
        progress: progress,
        pendingUploadCount: pendingUploadCount,
        compact: compact,
        showDropdownArrow: false,
        onTap: () {
          showAppSnackBar(context, message: 'Syncing… tap Cancel to stop');
        },
        onCancel: onCancel,
      );
    } else {
      child = SyncQuickSwitchGesture(
        longPressDelay: controller.appSettings.dragDelay,
        onCommit: (action) => runSyncManualAction(context, controller, action),
        child: PopupMenuButton<SyncManualAction>(
          tooltip: 'Sync: tap for menu, drag to choose',
          constraints: const BoxConstraints(
            minWidth: _menuMinWidth,
            maxWidth: _menuMaxWidth,
          ),
          onSelected: (action) =>
              runSyncManualAction(context, controller, action),
          itemBuilder: (_) => syncActionPopupMenuItems(),
          child: _SyncStatusTrigger(
            status: status,
            error: error,
            conflictCount: conflictCount,
            lastSyncedAt: lastSyncedAt,
            progress: progress,
            pendingUploadCount: pendingUploadCount,
            compact: compact,
            showDropdownArrow: true,
          ),
        ),
      );
    }

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: _appBarIconButtonSideInset),
      child: child,
    );
  }
}

class _SyncStatusTrigger extends StatelessWidget {
  const _SyncStatusTrigger({
    required this.status,
    required this.error,
    required this.conflictCount,
    required this.lastSyncedAt,
    required this.progress,
    required this.pendingUploadCount,
    required this.compact,
    required this.showDropdownArrow,
    this.onTap,
    this.onCancel,
  });

  final SyncStatus status;
  final String? error;
  final int conflictCount;
  final DateTime? lastSyncedAt;
  final SyncProgress? progress;
  final int pendingUploadCount;
  final bool compact;
  final bool showDropdownArrow;
  final VoidCallback? onTap;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = conflictCount > 0
        ? colorScheme.error
        : switch (status) {
            SyncStatus.error => colorScheme.error,
            SyncStatus.success => colorScheme.tertiary,
            SyncStatus.syncing => colorScheme.primary,
            SyncStatus.idle => null,
          };

    final syncing = status == SyncStatus.syncing;
    final label = conflictCount > 0
        ? '$conflictCount sync conflict(s)'
        : syncStatusWithLastSuccessLabel(
            status,
            lastSyncedAt,
            progress: progress,
            pendingUploadCount: pendingUploadCount,
          );
    final compactLabel = conflictCount > 0
        ? 'Conflicts: $conflictCount'
        : compactSyncStatusLabel(
            status,
            lastSyncedAt,
            progress: progress,
            pendingUploadCount: pendingUploadCount,
          );

    final lastSuccess = lastSyncedAt == null
        ? 'No successful sync yet'
        : 'Last successful sync: ${formatSyncTime(lastSyncedAt!)}';
    final pendingDetail =
        pendingUploadCount > 0 ? 'Workspace changes are not uploaded' : null;

    final progressDetail = progress == null
        ? null
        : [
            progress!.phaseLabel,
            if (progress!.hasTotal) '${progress!.completed}/${progress!.total}',
            if (progress!.skipped > 0) 'Skipped ${progress!.skipped} unchanged',
            if (progress!.currentLabel != null) progress!.currentLabel!,
          ].join(' · ');

    final tooltip = conflictCount > 0
        ? 'Sync conflicts need attention; open Conflict Center'
        : syncing
            ? (progressDetail == null
                ? 'Syncing… tap to cancel'
                : '$progressDetail\nTap to cancel')
            : error == null
                ? [
                    lastSuccess,
                    if (pendingDetail != null) pendingDetail,
                    'Tap for menu; drag to choose',
                  ].join('\n')
                : [
                    error!,
                    lastSuccess,
                    if (pendingDetail != null) pendingDetail,
                  ].join('\n');

    final icon = Icon(
      conflictCount > 0 ? Icons.warning_amber_outlined : syncStatusIcon(status),
      color: color,
      size: 20,
    );

    final trigger = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 112 : 220),
            child: Text(
              compact ? compactLabel : label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
          if (showDropdownArrow) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
              size: 20,
            ),
          ],
        ],
      ),
    );

    final cancelButton = onCancel == null
        ? null
        : IconButton(
            tooltip: 'Cancel sync',
            onPressed: onCancel,
            icon: Icon(
              Icons.close,
              color: colorScheme.onSurfaceVariant,
              size: 20,
            ),
          );

    final body = onTap == null
        ? trigger
        : TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: trigger,
          );

    return Semantics(
      liveRegion: true,
      label: syncing ? '$label; can cancel' : label,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: cancelButton == null
            ? body
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  body,
                  cancelButton,
                ],
              ),
      ),
    );
  }
}
