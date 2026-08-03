import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/board_controller.dart';
import '../features/activity/activity_screen.dart';
import '../features/import_export/backup_file_picker.dart';
import '../features/labels/label_management_screen.dart';
import '../features/project/project_settings_screen.dart';
import '../features/statistics/statistics_screen.dart';
import '../features/trash/trash_screen.dart';
import '../settings/settings_section.dart';
import '../webdav_sync/webdav_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;
  late final TextEditingController _pathController;

  bool _enabled = false;
  bool _autoSync = true;
  int _pollSeconds = WebDavConfig.defaultPollIntervalSeconds;
  int _pushDebounceSeconds = WebDavConfig.defaultPushDebounceSeconds;
  int _dragLongPressMs = 500;
  bool _obscurePassword = true;
  bool _testing = false;
  bool _saving = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final controller = context.read<BoardController>();
    final config = controller.webDavConfig;
    _enabled = config.enabled;
    _autoSync = config.autoSync;
    _pollSeconds =
        WebDavConfig.clampPollIntervalSeconds(config.pollIntervalSeconds);
    _pushDebounceSeconds =
        WebDavConfig.clampPushDebounceSeconds(config.pushDebounceSeconds);
    _dragLongPressMs = controller.appSettings.dragLongPressMs;
    _urlController = TextEditingController(text: config.serverUrl);
    _userController = TextEditingController(text: config.username);
    _passController = TextEditingController(text: config.password);
    _pathController = TextEditingController(text: config.remotePath);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  WebDavConfig _buildConfig() {
    return WebDavConfig(
      enabled: _enabled,
      serverUrl: _urlController.text.trim(),
      username: _userController.text.trim(),
      password: _passController.text,
      remotePath: _pathController.text.trim().isEmpty
          ? '/KanbanApp'
          : _pathController.text.trim(),
      autoSync: _autoSync,
      pollIntervalSeconds: WebDavConfig.clampPollIntervalSeconds(_pollSeconds),
      pushDebounceSeconds:
          WebDavConfig.clampPushDebounceSeconds(_pushDebounceSeconds),
    );
  }

  String _formatPollInterval(int seconds) {
    final clamped = WebDavConfig.clampPollIntervalSeconds(seconds);
    if (clamped % 60 == 0) {
      return '${clamped ~/ 60} 分钟';
    }
    return '$clamped 秒';
  }

  String _formatPushDebounce(int seconds) {
    return '${WebDavConfig.clampPushDebounceSeconds(seconds)} 秒';
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final ok = await context.read<BoardController>().testWebDav(_buildConfig());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = ok ? '连接成功' : '连接失败，请检查地址与账号';
    });
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await context.read<BoardController>().saveWebDavConfig(_buildConfig());
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存，变更将自动同步到网盘')),
    );
    Navigator.pop(context);
  }

  Future<void> _exportBackup() async {
    final controller = context.read<BoardController>();
    final bytes = await controller.createBackupArchive();
    final now = DateTime.now();
    final fileName =
        'kanban-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.kanban-backup';
    final saved = await saveBackupFile(bytes, fileName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved ? '完整备份已导出' : '已取消导出')),
    );
  }

  Future<void> _importBackup() async {
    final bytes = await pickBackupFile();
    if (!mounted || bytes == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复完整备份？'),
        content: const Text('当前工作区会被备份内容替换。建议先导出当前数据。'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('备份已恢复')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份无效：${error.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final doneColumnName =
        context.watch<BoardController>().projectSettings.doneColumnName;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Form(
        key: _formKey,
        child: ListView(
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
                  onChanged: (v) =>
                      setState(() => _dragLongPressMs = v.round()),
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
                  subtitle: '请求系统通知权限并重新安排提醒',
                  onTap: () async {
                    await context
                        .read<BoardController>()
                        .initializeReminders(requestPermission: true);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('提醒设置已更新')),
                    );
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
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              icon: Icons.cloud_outlined,
              title: 'WebDAV 同步',
              subtitle: '连接配置仅保存在本机',
              children: [
                SwitchListTile(
                  title: const Text('启用 WebDAV 同步'),
                  subtitle: const Text('开启后，新增/修改卡片会自动上传'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _enabled
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '开启后可配置服务器连接与自动同步',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          '连接信息',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _urlController,
                              decoration: const InputDecoration(
                                labelText: '服务器地址',
                                hintText: 'https://dav.jianguoyun.com/dav/',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) {
                                if (!_enabled) return null;
                                if (v == null || v.trim().isEmpty) {
                                  return '请输入服务器地址';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _userController,
                              decoration: const InputDecoration(
                                labelText: '用户名',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) {
                                if (!_enabled) return null;
                                if (v == null || v.trim().isEmpty) {
                                  return '请输入用户名';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: '密码 / 应用密码',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                              validator: (v) {
                                if (!_enabled) return null;
                                if (v == null || v.isEmpty) return '请输入密码';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _pathController,
                              decoration: const InputDecoration(
                                labelText: '远端目录路径',
                                hintText: '/KanbanApp',
                                border: OutlineInputBorder(),
                                isDense: true,
                                helperText:
                                    '数据目录：projects.json + projects/{项目id}/',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          '同步行为',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('自动同步'),
                        subtitle: Text(
                          '本地变更后约 $_pushDebounceSeconds 秒自动上传',
                        ),
                        value: _autoSync,
                        onChanged: (v) => setState(() => _autoSync = v),
                      ),
                      if (_autoSync)
                        SettingsSliderRow(
                          title: '变更后上传延迟',
                          description: '停止编辑后再上传；本地会立刻保存，仅延迟云端请求',
                          value: _pushDebounceSeconds.toDouble(),
                          valueLabel: _formatPushDebounce(_pushDebounceSeconds),
                          min: WebDavConfig.minPushDebounceSeconds.toDouble(),
                          max: WebDavConfig.maxPushDebounceSeconds.toDouble(),
                          divisions: WebDavConfig.maxPushDebounceSeconds -
                              WebDavConfig.minPushDebounceSeconds,
                          onChanged: (v) => setState(
                            () => _pushDebounceSeconds =
                                WebDavConfig.clampPushDebounceSeconds(
                              v.round(),
                            ),
                          ),
                        ),
                      SettingsSliderRow(
                        title: '后台拉取间隔',
                        description: '定期从网盘拉取更新；范围 1–10 分钟，避免频繁请求触发限流',
                        value: _pollSeconds.toDouble(),
                        valueLabel: _formatPollInterval(_pollSeconds),
                        min: WebDavConfig.minPollIntervalSeconds.toDouble(),
                        max: WebDavConfig.maxPollIntervalSeconds.toDouble(),
                        divisions: (WebDavConfig.maxPollIntervalSeconds -
                                WebDavConfig.minPollIntervalSeconds) ~/
                            60,
                        onChanged: (v) => setState(
                          () => _pollSeconds =
                              WebDavConfig.clampPollIntervalSeconds(v.round()),
                        ),
                      ),
                      if (_testResult != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Row(
                            children: [
                              Icon(
                                _testResult == '连接成功'
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                size: 18,
                                color: _testResult == '连接成功'
                                    ? Colors.green
                                    : Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _testResult!,
                                style: TextStyle(
                                  color: _testResult == '连接成功'
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            OutlinedButton(
                              onPressed: _testing ? null : _testConnection,
                              child: _testing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('测试连接'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _saving ? null : _save,
                                child: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('保存'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
