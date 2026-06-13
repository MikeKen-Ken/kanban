import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/board_controller.dart';
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
    _pollSeconds = config.pollIntervalSeconds;
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
          ? '/KanbanApp/board.json'
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
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              title: const Text('启用 WebDAV 同步'),
              subtitle: const Text('开启后，新增/修改卡片会自动上传，无需手动导出'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://dav.jianguoyun.com/dav/',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (!_enabled) return null;
                if (v == null || v.trim().isEmpty) return '请输入服务器地址';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _userController,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (!_enabled) return null;
                if (v == null || v.trim().isEmpty) return '请输入用户名';
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
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
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
                labelText: '远端文件路径',
                hintText: '/KanbanApp/board.json',
                border: OutlineInputBorder(),
                helperText: '看板数据在网盘上的 JSON 文件路径',
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('自动同步'),
              subtitle: const Text('本地变更后约 1.5 秒自动上传'),
              value: _autoSync,
              onChanged: (v) => setState(() => _autoSync = v),
            ),
            ListTile(
              title: const Text('后台拉取间隔'),
              subtitle: Slider(
                value: _pollSeconds.toDouble(),
                min: 15,
                max: 120,
                divisions: 7,
                label: '$_pollSeconds 秒',
                onChanged: (v) => setState(() => _pollSeconds = v.round()),
              ),
              trailing: Text('${_pollSeconds}s'),
            ),
            if (_testResult != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _testResult!,
                  style: TextStyle(
                    color: _testResult == '连接成功'
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 24),
            Text(
              '说明\n'
              '· 坚果云：在账户设置中开启 WebDAV，使用应用密码\n'
              '· 无需向任何机构申请 WebDAV 资质\n'
              '· 多设备通过同一远端文件自动同步',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
