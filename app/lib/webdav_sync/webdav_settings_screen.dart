import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/board_controller.dart';
import '../settings/settings_section.dart';
import 'webdav_config.dart';
import '../common/app_snack_bar.dart';

/// WebDAV 同步详细设置页（连接配置仅保存在本机）
class WebDavSettingsScreen extends StatefulWidget {
  const WebDavSettingsScreen({super.key});

  @override
  State<WebDavSettingsScreen> createState() => _WebDavSettingsScreenState();
}

class _WebDavSettingsScreenState extends State<WebDavSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;
  late final TextEditingController _pathController;

  bool _enabled = false;
  bool _autoSync = true;
  bool _autoPull = true;
  int _pollSeconds = WebDavConfig.defaultPollIntervalSeconds;
  int _pushDebounceSeconds = WebDavConfig.defaultPushDebounceSeconds;
  bool _obscurePassword = true;
  bool _testing = false;
  bool _saving = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final config = context.read<BoardController>().webDavConfig;
    _enabled = config.enabled;
    _autoSync = config.autoSync;
    _autoPull = config.autoPull;
    _pollSeconds =
        WebDavConfig.clampPollIntervalSeconds(config.pollIntervalSeconds);
    _pushDebounceSeconds =
        WebDavConfig.clampPushDebounceSeconds(config.pushDebounceSeconds);
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
      autoPull: _autoPull,
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await context.read<BoardController>().saveWebDavConfig(_buildConfig());
    if (!mounted) return;
    setState(() => _saving = false);
    final tip = !_enabled
        ? '已保存'
        : (!_autoSync && !_autoPull)
            ? '已保存；仅手动同步（点顶栏同步按钮）'
            : '已保存';
    showAppSnackBar(context, message: tip);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SettingsSection(
              icon: Icons.cloud_outlined,
              title: '同步开关',
              subtitle: '连接配置仅保存在本机，不同步',
              children: [
                SwitchListTile(
                  title: const Text('启用 WebDAV 同步'),
                  subtitle: const Text('开启后可配置连接；上传/拉取是否自动见下方开关'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                if (!_enabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '开启后可配置服务器连接与同步行为',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
              ],
            ),
            if (_enabled) ...[
              const SizedBox(height: 16),
              SettingsSection(
                icon: Icons.link_outlined,
                title: '连接信息',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
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
                ],
              ),
              const SizedBox(height: 16),
              SettingsSection(
                icon: Icons.sync_outlined,
                title: '同步行为',
                children: [
                  SwitchListTile(
                    title: const Text('自动上传'),
                    subtitle: Text(
                      _autoSync
                          ? '本地变更后约 $_pushDebounceSeconds 秒自动上传'
                          : '关闭后仅手动同步时上传',
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
                            WebDavConfig.clampPushDebounceSeconds(v.round()),
                      ),
                    ),
                  SwitchListTile(
                    title: const Text('自动拉取'),
                    subtitle: Text(
                      _autoPull
                          ? '启动时拉取，并按间隔后台拉取'
                          : '关闭后仅手动同步时拉取',
                    ),
                    value: _autoPull,
                    onChanged: (v) => setState(() => _autoPull = v),
                  ),
                  if (_autoPull)
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
                ],
              ),
              const SizedBox(height: 16),
              if (_testResult != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
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
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _testing ? null : _testConnection,
                    child: _testing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
            if (!_enabled) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
