import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/board_controller.dart';
import '../features/project/project_settings_screen.dart';
import '../settings/app_settings.dart';
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
  int _pollSeconds = 30;
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
    _pollSeconds = config.pollIntervalSeconds;
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
      pollIntervalSeconds: _pollSeconds,
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final ok =
        await context.read<BoardController>().testWebDav(_buildConfig());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = ok ? '连接成功' : '连接失败，请检查地址与账号';
    });
  }

  Future<void> _saveDragSettings(int ms) async {
    await context.read<BoardController>().saveAppSettings(
          AppSettings(dragLongPressMs: ms),
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
                      ? '按下即可拖动卡片'
                      : '按住 ${_dragLongPressMs}ms 后开始拖动',
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
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              icon: Icons.sync_outlined,
              title: '同步范围',
              subtitle: '了解哪些数据会上传到网盘',
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: _SyncScopeInfo(),
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
                        subtitle: const Text('本地变更后约 1.5 秒自动上传'),
                        value: _autoSync,
                        onChanged: (v) => setState(() => _autoSync = v),
                      ),
                      SettingsSliderRow(
                        title: '后台拉取间隔',
                        description: '应用在后台时定期从网盘拉取更新',
                        value: _pollSeconds.toDouble(),
                        valueLabel: '${_pollSeconds}s',
                        min: 15,
                        max: 120,
                        divisions: 7,
                        onChanged: (v) =>
                            setState(() => _pollSeconds = v.round()),
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _WebDavHelpBox(),
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

class _SyncScopeInfo extends StatelessWidget {
  const _SyncScopeInfo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SyncScopeGroup(
          icon: Icons.cloud_done_outlined,
          iconColor: Colors.green.shade700,
          title: '会同步到 WebDAV',
          items: const [
            '项目列表（projects.json）',
            '各项目看板数据（列、卡片、列颜色）',
            '各项目设置（已完成列名称）',
          ],
        ),
        const SizedBox(height: 12),
        _SyncScopeGroup(
          icon: Icons.smartphone_outlined,
          iconColor: theme.colorScheme.onSurfaceVariant,
          title: '仅本机，不同步',
          items: const [
            '当前选中的项目（每台设备可不同）',
            '拖拽按压时长（交互偏好）',
            'WebDAV 连接配置与密码',
          ],
        ),
      ],
    );
  }
}

class _SyncScopeGroup extends StatelessWidget {
  const _SyncScopeGroup({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '· ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebDavHelpBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '使用说明',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '坚果云：在账户设置中开启 WebDAV，使用应用密码\n'
            '无需向任何机构申请 WebDAV 资质\n'
            '多设备通过同一远端目录自动同步项目与看板数据',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
