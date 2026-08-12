import 'package:flutter/material.dart';

import 'agent_dispatch_credentials.dart';

/// Cursor SDK 凭据编辑区。输入内容不会写入普通设置或运行日志。
class CursorApiKeySection extends StatefulWidget {
  const CursorApiKeySection({
    super.key,
    required this.enabled,
    this.credentials = const AgentDispatchCredentials(),
  });

  final bool enabled;
  final AgentDispatchCredentials credentials;

  @override
  State<CursorApiKeySection> createState() => _CursorApiKeySectionState();
}

class _CursorApiKeySectionState extends State<CursorApiKeySection> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _hasStoredKey = false;
  bool _hasEnvironmentKey = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    try {
      final stored = await widget.credentials.readStoredCursorApiKey();
      final environment = widget.credentials.readEnvironmentCursorApiKey();
      if (!mounted) return;
      setState(() {
        _hasStoredKey = stored != null;
        _hasEnvironmentKey = environment != null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '读取安全存储失败：$error');
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.credentials.saveCursorApiKey(_controller.text);
      _controller.clear();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _hasStoredKey = true;
        _message = 'Cursor API Key 已保存，并已通过安全存储读回验证';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '$error';
      });
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.credentials.deleteCursorApiKey();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _hasStoredKey = false;
        _message = _hasEnvironmentKey
            ? '已删除安全存储中的 Key；仍会使用环境变量 CURSOR_API_KEY'
            : '已删除 Cursor API Key';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '删除失败：$error';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = _hasStoredKey || _hasEnvironmentKey;
    final enabled = widget.enabled && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Cursor API Key',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 8),
            Icon(
              available ? Icons.check_circle_outline : Icons.info_outline,
              size: 18,
              color: available
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _hasStoredKey
                    ? '已安全保存'
                    : _hasEnvironmentKey
                        ? '已检测到环境变量'
                        : '尚未配置',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _controller,
          enabled: enabled,
          obscureText: _obscure,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: available ? '输入新 Key 可覆盖当前凭据' : '粘贴 Cursor API Key',
            helperText: '仅用于 Cursor SDK；不会写入仓库、偏好或运行日志',
            suffixIcon: IconButton(
              tooltip: _obscure ? '显示' : '隐藏',
              onPressed:
                  enabled ? () => setState(() => _obscure = !_obscure) : null,
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            ),
          ),
          onSubmitted: enabled ? (_) => _save() : null,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: enabled ? _save : null,
              icon: const Icon(Icons.key, size: 18),
              label: const Text('安全保存'),
            ),
            if (_hasStoredKey)
              TextButton(
                onPressed: enabled ? _delete : null,
                child: const Text('删除已保存 Key'),
              ),
          ],
        ),
        if (_message != null)
          Text(_message!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
