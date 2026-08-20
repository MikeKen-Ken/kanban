import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/app_snack_bar.dart';
import '../controllers/board_controller.dart';
import '../features/activity/activity_screen.dart';
import '../features/app_update/app_update_screen.dart';
import '../features/completed_auto_clear/completed_auto_clear.dart';
import '../features/import_export/backup_file_picker.dart';
import '../features/import_export/backup_history_screen.dart';
import '../features/labels/label_management_screen.dart';
import '../features/mcp/kanban_mcp_host.dart';
import '../features/mcp/mcp_constants.dart';
import '../features/mcp/mcp_paths.dart';
import '../features/mcp/mcp_settings_screen.dart';
import '../features/project/project_settings_screen.dart';
import '../features/statistics/statistics_screen.dart';
import '../features/trash/trash_screen.dart';
import '../settings/settings_section.dart';
import '../webdav_sync/webdav_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _openCategory({
    required String title,
    required List<Widget> children,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsCategoryScreen(
          title: title,
          children: children,
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    final controller = context.read<BoardController>();
    final bytes = await controller.createBackupArchive();
    final now = DateTime.now();
    final fileName =
        'kanban-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.kanban-backup';
    final saved = await saveBackupFile(bytes, fileName);
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: saved ? 'Full backup exported' : 'Export canceled',
    );
  }

  Future<void> _importBackup() async {
    final bytes = await pickBackupFile();
    if (!mounted || bytes == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore full backup?'),
        content: const Text(
            'The current workspace will be replaced by the backup. A point-in-time backup will be created first.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<BoardController>().restoreBackupArchive(bytes);
      if (!mounted) return;
      showAppSnackBar(context, message: 'Backup restored');
    } on FormatException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'Invalid backup: ${error.message}');
    }
  }

  String _webDavSubtitle(bool enabled, String serverUrl) {
    if (!enabled)
      return 'Disabled · connection settings are stored locally only';
    final host = serverUrl.trim();
    if (host.isEmpty)
      return 'Enabled · server address is not set · connection settings are stored locally only';
    return 'Enabled · $host · manual upload/download/merge';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SettingsNavigationCard(
            icon: Icons.touch_app_outlined,
            title: 'Interaction',
            subtitle: 'Stored locally only; not synced',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const _InteractionSettingsPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          SettingsNavigationCard(
            icon: Icons.palette_outlined,
            title: 'Appearance & reminders',
            subtitle: 'Stored locally only',
            onTap: () => _openCategory(
              title: 'Appearance & reminders',
              children: [
                Selector<BoardController, ThemeMode>(
                  selector: (_, controller) => controller.appSettings.themeMode,
                  builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (selection) {
                      final controller = context.read<BoardController>();
                      controller.saveAppSettings(
                        controller.appSettings.copyWith(
                          themeMode: selection.single,
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
                SettingsNavigationTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Enable task reminders',
                  subtitle:
                      'Notification permission is requested on first launch; you can enable it again here',
                  onTap: () async {
                    final result = await context
                        .read<BoardController>()
                        .enableRemindersFromSettings();
                    if (!context.mounted) return;
                    final message = switch (result) {
                      NotificationPermissionResult.enabled =>
                        'Notifications enabled and reminders rescheduled',
                      NotificationPermissionResult.openedSystemSettings =>
                        'Allow notifications in system settings, then return',
                      NotificationPermissionResult.denied =>
                        'Could not enable notifications. Allow this app in system settings',
                    };
                    showAppSnackBar(context, message: message);
                  },
                ),
                SettingsNavigationTile(
                  icon: Icons.insights_outlined,
                  title: 'Workspace statistics',
                  subtitle:
                      'View task totals, overdue items, and completion trends',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StatisticsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Selector<BoardController, int>(
            selector: (_, c) => c.appSettings.customLabels.length,
            builder: (context, count, _) => SettingsNavigationCard(
              icon: Icons.label_outline,
              title: 'Labels',
              subtitle: count > 0
                  ? '$count custom labels · synced with the workspace'
                  : 'Add, rename, recolor, or delete · synced with the workspace',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LabelManagementScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SettingsNavigationCard(
            icon: Icons.inventory_2_outlined,
            title: 'Import & export',
            subtitle:
                'Includes all projects, settings, shared content, and attachments',
            onTap: () => _openCategory(
              title: 'Import & export',
              children: [
                if (context.read<BoardController>().backupHistorySupported)
                  SettingsNavigationTile(
                    icon: Icons.history_toggle_off,
                    title: 'Point-in-time backup',
                    subtitle:
                        'Automatic backup every 10 minutes · expired files can be cleaned up',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BackupHistoryScreen(),
                        ),
                      );
                    },
                  ),
                SettingsNavigationTile(
                  icon: Icons.file_upload_outlined,
                  title: 'Export full backup',
                  subtitle: 'Save as a .kanban-backup file',
                  onTap: _exportBackup,
                ),
                SettingsNavigationTile(
                  icon: Icons.file_download_outlined,
                  title: 'Restore full backup',
                  subtitle: 'Replaces the current workspace',
                  onTap: _importBackup,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Selector<BoardController, String>(
            selector: (_, c) => c.projectSettings.doneColumnName,
            builder: (context, doneColumnName, _) => SettingsNavigationCard(
              icon: Icons.folder_outlined,
              title: 'Current project',
              subtitle: 'Settings sync to WebDAV with the project',
              onTap: () => _openCategory(
                title: 'Current project',
                children: [
                  SettingsNavigationTile(
                    icon: Icons.tune_outlined,
                    title: 'Project settings',
                    subtitle: 'Done column: $doneColumnName',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ProjectSettingsScreen(),
                        ),
                      );
                    },
                  ),
                  SettingsNavigationTile(
                    icon: Icons.history,
                    title: 'Activity history',
                    subtitle: 'View recent card changes in the current project',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ActivityScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SettingsNavigationCard(
            icon: Icons.delete_outline,
            title: 'Trash',
            subtitle:
                'Deleted cards, columns, and projects can be restored here',
            onTap: () => _openCategory(
              title: 'Trash',
              children: [
                Selector<BoardController, int>(
                  selector: (_, c) => c.trashItemCount,
                  builder: (context, count, _) => SettingsNavigationTile(
                    icon: Icons.restore_from_trash_outlined,
                    title: 'Open trash',
                    subtitle:
                        count > 0 ? '$count items pending' : 'Trash is empty',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const TrashScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
                Selector<BoardController, bool>(
                  selector: (_, c) => c.appSettings.confirmBeforeDeleteCard,
                  builder: (context, confirm, _) => SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    secondary: Icon(
                      Icons.warning_amber_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: const Text('Confirm before deleting'),
                    subtitle: Text(
                      confirm
                          ? 'A confirmation dialog appears before deleting a card'
                          : 'Off: delete from the context menu or details goes directly to Trash',
                    ),
                    value: confirm,
                    onChanged: (value) {
                      final controller = context.read<BoardController>();
                      controller.saveAppSettings(
                        controller.appSettings.copyWith(
                          confirmBeforeDeleteCard: value,
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
                Selector<BoardController, int>(
                  selector: (_, c) => c.appSettings.completedAutoClearDays,
                  builder: (context, days, _) {
                    final options = [
                      ...completedAutoClearDayOptions,
                      if (!completedAutoClearDayOptions.contains(days)) days,
                    ]..sort();
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Icon(
                        Icons.auto_delete_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Auto-clear completed'),
                      subtitle: Text(
                        days <= 0
                            ? 'Off: completed cards are not deleted automatically'
                            : 'Completed cards older than $days days move to Trash',
                      ),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: days,
                          items: [
                            for (final option in options)
                              DropdownMenuItem(
                                value: option,
                                child:
                                    Text(completedAutoClearDaysLabel(option)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            final controller = context.read<BoardController>();
                            controller.saveAppSettings(
                              controller.appSettings.copyWith(
                                completedAutoClearDays: value,
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (McpPaths.isWindowsSupported)
            ListenableBuilder(
              listenable: context.read<BoardController>().mcpHost,
              builder: (context, _) {
                final controller = context.watch<BoardController>();
                final enabled = controller.appSettings.mcpEnabled;
                final host = controller.mcpHost;
                final status = !enabled
                    ? 'Disabled'
                    : host.isRunning
                        ? 'Running'
                        : (host.status == KanbanMcpStatus.error
                            ? 'Failed to start'
                            : 'Not running');
                return SettingsNavigationCard(
                  icon: Icons.hub_outlined,
                  title: 'MCP / AI control',
                  subtitle:
                      '$status · ${McpConstants.endpointUrl(controller.appSettings.mcpPort)} · local configuration, not synced',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const McpSettingsScreen(),
                      ),
                    );
                  },
                );
              },
            ),
          if (McpPaths.isWindowsSupported) const SizedBox(height: 16),
          Selector<BoardController, (bool, String)>(
            selector: (_, c) => (
              c.webDavConfig.enabled,
              c.webDavConfig.serverUrl,
            ),
            builder: (context, state, _) {
              final (enabled, serverUrl) = state;
              return SettingsNavigationCard(
                icon: Icons.cloud_outlined,
                title: 'WebDAV sync',
                subtitle: _webDavSubtitle(enabled, serverUrl),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WebDavSettingsScreen(),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          SettingsNavigationCard(
            icon: Icons.system_update_alt_outlined,
            title: 'Check for updates',
            subtitle:
                'Get releases from GitHub; install the APK on Android, or replace the Windows directory and restart',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AppUpdateScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InteractionSettingsPage extends StatefulWidget {
  const _InteractionSettingsPage();

  @override
  State<_InteractionSettingsPage> createState() =>
      _InteractionSettingsPageState();
}

class _InteractionSettingsPageState extends State<_InteractionSettingsPage> {
  late int _dragLongPressMs;

  @override
  void initState() {
    super.initState();
    _dragLongPressMs =
        context.read<BoardController>().appSettings.dragLongPressMs;
  }

  Future<void> _saveDragSettings(int ms) async {
    final controller = context.read<BoardController>();
    await controller.saveAppSettings(
      controller.appSettings.copyWith(dragLongPressMs: ms),
    );
  }

  String get _dragDurationLabel {
    if (_dragLongPressMs <= 0) return 'Immediate drag';
    return '${_dragLongPressMs}ms';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCategoryScreen(
      title: 'Interaction',
      children: [
        SettingsSliderRow(
          title: 'Drag press duration',
          description: _dragLongPressMs <= 0
              ? 'Hold and move to drag; long-press to open the transfer/delete menu'
              : 'Hold for ${_dragLongPressMs}ms, then drag; on touch devices use the card menu or Details > Transfer',
          value: _dragLongPressMs.toDouble(),
          valueLabel: _dragDurationLabel,
          min: 0,
          max: 1500,
          divisions: 15,
          onChanged: (v) => setState(() => _dragLongPressMs = v.round()),
          onChangeEnd: (v) => _saveDragSettings(v.round()),
        ),
      ],
    );
  }
}
