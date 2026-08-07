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
  int _dragLongPressMs = 200;

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
    if (_dragLongPressMs <= 0) return '即时拖拽';
    return '${_dragLongPressMs}ms';
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
      message: saved ? '完整备份已导出' : '已取消导出',
    );
  }

  Future<void> _importBackup() async {
    final bytes = await pickBackupFile();
    if (!mounted || bytes == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复完整备份？'),
        content: const Text('当前工作区会被备份内容替换，恢复前将自动创建时间点备份。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<BoardController>().restoreBackupArchive(bytes);
      if (!mounted) return;
      showAppSnackBar(context, message: '备份已恢复');
    } on FormatException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: '备份无效：${error.message}');
    }
  }

  String _webDavSubtitle(bool enabled, String serverUrl) {
    if (!enabled) return '未启用 · 连接配置仅保存在本机';
    final host = serverUrl.trim();
    if (host.isEmpty) return '已启用 · 尚未填写服务器地址';
    return '已启用 · $host';
  }

  @override
  Widget build(BuildContext context) {
    final doneColumnName =
        context.watch<BoardController>().projectSettings.doneColumnName;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SettingsSection(
            icon: Icons.touch_app_outlined,
            title: '交互',
            subtitle: '仅保存在本机，不同步',
            children: [
              SettingsSliderRow(
                title: '拖拽按压时长',
                description: _dragLongPressMs <= 0
                    ? '按住卡片并移动即可拖动'
                    : '按住卡片 ${_dragLongPressMs}ms 后再拖动',
                value: _dragLongPressMs.toDouble(),
                valueLabel: _dragDurationLabel,
                min: 0,
                max: 1500,
                divisions: 15,
                onChanged: (v) => setState(() => _dragLongPressMs = v.round()),
                onChangeEnd: (v) => _saveDragSettings(v.round()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            icon: Icons.palette_outlined,
            title: '外观与提醒',
            subtitle: '仅保存在本机',
            children: [
              Selector<BoardController, ThemeMode>(
                selector: (_, controller) => controller.appSettings.themeMode,
                builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('跟随系统'),
                      icon: Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('浅色'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('深色'),
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
                title: '启用任务提醒',
                subtitle: '首次启动会申请通知权限；也可在此重新启用',
                onTap: () async {
                  final result = await context
                      .read<BoardController>()
                      .enableRemindersFromSettings();
                  if (!context.mounted) return;
                  final message = switch (result) {
                    NotificationPermissionResult.enabled => '通知已启用，提醒已重新安排',
                    NotificationPermissionResult.openedSystemSettings =>
                      '请在系统设置中允许通知后返回',
                    NotificationPermissionResult.denied =>
                      '未能开启通知，请在系统设置中允许本应用通知',
                  };
                  showAppSnackBar(context, message: message);
                },
              ),
              SettingsNavigationTile(
                icon: Icons.insights_outlined,
                title: '工作区统计',
                subtitle: '查看任务总量、逾期和完成趋势',
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
          const SizedBox(height: 16),
          SettingsSection(
            icon: Icons.label_outline,
            title: '标签',
            subtitle: '自定义标签会随工作区同步',
            children: [
              Selector<BoardController, int>(
                selector: (_, c) => c.appSettings.customLabels.length,
                builder: (context, count, _) => SettingsNavigationTile(
                  icon: Icons.label_important_outline,
                  title: '标签管理',
                  subtitle: count > 0 ? '$count 个自定义标签' : '新增、改名、改色或删除',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LabelManagementScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            icon: Icons.inventory_2_outlined,
            title: '导入与导出',
            subtitle: '包含全部项目、设置、共享内容和附件',
            children: [
              if (context.read<BoardController>().backupHistorySupported)
                SettingsNavigationTile(
                  icon: Icons.history_toggle_off,
                  title: '时间点备份',
                  subtitle: '每 10 分钟自动备份 · 保留最近 7 天',
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
                title: '导出完整备份',
                subtitle: '保存为 .kanban-backup 文件',
                onTap: _exportBackup,
              ),
              SettingsNavigationTile(
                icon: Icons.file_download_outlined,
                title: '恢复完整备份',
                subtitle: '将替换当前工作区',
                onTap: _importBackup,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            icon: Icons.folder_outlined,
            title: '当前项目',
            subtitle: '设置会随项目同步到 WebDAV',
            children: [
              SettingsNavigationTile(
                icon: Icons.tune_outlined,
                title: '项目设置',
                subtitle: '已完成列：$doneColumnName',
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
                title: '活动历史',
                subtitle: '查看当前项目最近的卡片变更',
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
          const SizedBox(height: 16),
          SettingsSection(
            icon: Icons.delete_outline,
            title: '回收站',
            subtitle: '已删除的卡片、列、项目可在此还原',
            children: [
              Selector<BoardController, int>(
                selector: (_, c) => c.trashItemCount,
                builder: (context, count, _) => SettingsNavigationTile(
                  icon: Icons.restore_from_trash_outlined,
                  title: '打开回收站',
                  subtitle: count > 0 ? '$count 项待处理' : '回收站为空',
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
                  title: const Text('删除前确认'),
                  subtitle: Text(
                    confirm
                        ? '删除卡片前会弹出确认对话框'
                        : '关闭：右键/详情删除直接进入回收站',
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
                    title: const Text('自动清空已完成'),
                    subtitle: Text(
                      days <= 0
                          ? '关闭：不会自动删除已完成卡片'
                          : '超过 $days 天的已完成卡片会移入回收站',
                    ),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: days,
                        items: [
                          for (final option in options)
                            DropdownMenuItem(
                              value: option,
                              child: Text(completedAutoClearDaysLabel(option)),
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
          const SizedBox(height: 16),
          if (McpPaths.isWindowsSupported)
            SettingsSection(
              icon: Icons.hub_outlined,
              title: 'MCP / AI 控制',
              subtitle: '本机 Cursor / Codex 读写任务；不同步',
              children: [
                ListenableBuilder(
                  listenable: context.read<BoardController>().mcpHost,
                  builder: (context, _) {
                    final controller = context.watch<BoardController>();
                    final enabled = controller.appSettings.mcpEnabled;
                    final host = controller.mcpHost;
                    final status = !enabled
                        ? '已关闭'
                        : host.isRunning
                            ? '运行中'
                            : (host.status == KanbanMcpStatus.error
                                ? '启动失败'
                                : '未运行');
                    return SettingsNavigationTile(
                      icon: Icons.smart_toy_outlined,
                      title: 'MCP 设置',
                      subtitle:
                          '$status · ${McpConstants.endpointUrl(controller.appSettings.mcpPort)}',
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
              ],
            ),
          if (McpPaths.isWindowsSupported) const SizedBox(height: 16),
          SettingsSection(
            icon: Icons.cloud_outlined,
            title: 'WebDAV 同步',
            subtitle: '连接配置仅保存在本机',
            children: [
              Selector<BoardController, (bool, String)>(
                selector: (_, c) => (
                  c.webDavConfig.enabled,
                  c.webDavConfig.serverUrl,
                ),
                builder: (context, state, _) {
                  final (enabled, serverUrl) = state;
                  return SettingsNavigationTile(
                    icon: Icons.cloud_sync_outlined,
                    title: 'WebDAV 设置',
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
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            icon: Icons.system_update_alt_outlined,
            title: '关于与更新',
            subtitle: '从 GitHub Release 下载安装包',
            children: [
              SettingsNavigationTile(
                icon: Icons.download_outlined,
                title: '检查更新',
                subtitle: 'Android 安装 APK；Windows 同目录覆盖后重启',
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
        ],
      ),
    );
  }
}
