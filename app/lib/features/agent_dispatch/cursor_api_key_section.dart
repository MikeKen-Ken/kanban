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
  final _labelController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _hasEnvironmentKey = false;
  List<CursorApiKeySummary> _keys = const [];
  String? _message;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    try {
      final keys = await widget.credentials.listStoredCursorApiKeys();
      final environment = widget.credentials.readEnvironmentCursorApiKey();
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _hasEnvironmentKey = environment != null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '读取安全存储失败：$error');
    }
  }

  CursorApiKeySummary? get _activeKey {
    for (final item in _keys) {
      if (item.isActive) return item;
    }
    return _keys.isEmpty ? null : _keys.first;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final label = _labelController.text.trim();
      if (label.isEmpty && _activeKey != null) {
        await widget.credentials.replaceActiveCursorApiKey(_controller.text);
      } else {
        await widget.credentials.saveCursorApiKey(
          _controller.text,
          label: _labelController.text,
        );
      }
      _controller.clear();
      _labelController.clear();
      await _refreshStatus();
      if (!mounted) return;
      setState(() {
        _busy = false;
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

  Future<void> _selectKey(String id) async {
    if (_busy) return;
    CursorApiKeySummary? selected;
    for (final item in _keys) {
      if (item.id == id) {
        selected = item;
        break;
      }
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.credentials.setActiveCursorApiKey(id);
      await _refreshStatus();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _controller.clear();
        if (selected != null) {
          _labelController.text = selected.label;
        }
        _message = '已切换当前 Key';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '$error';
      });
    }
  }

  Future<void> _delete(String id) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.credentials.deleteCursorApiKey(id);
      await _refreshStatus();
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (_activeKey?.id == id) {
          _controller.clear();
          _labelController.clear();
        }
        _message = _keys.isEmpty && _hasEnvironmentKey
            ? '已删除该 Key；仍会使用环境变量 CURSOR_API_KEY'
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
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeKey;
    final available = _keys.isNotEmpty || _hasEnvironmentKey;
    final enabled = widget.enabled && !_busy;
    final statusText = active != null
        ? '当前：${active.label}'
        : _hasEnvironmentKey
            ? '已检测到环境变量'
            : '尚未配置';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              available ? Icons.check_circle_outline : Icons.info_outline,
              size: 16,
              color: available
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                statusText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: enabled,
                obscureText: _obscure,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: available
                      ? '输入新 Key 可替换当前 Key'
                      : '粘贴 Cursor API Key',
                  suffixIcon: PopupMenuButton<String>(
                    tooltip: '展开已保存 Key',
                    enabled: enabled && _keys.isNotEmpty,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_drop_down),
                    onSelected: _selectKey,
                    itemBuilder: (context) => [
                      for (final item in _keys)
                        PopupMenuItem(
                          value: item.id,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Row(
                              children: [
                                if (item.isActive)
                                  Icon(
                                    Icons.check,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  )
                                else
                                  const SizedBox(width: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '删除此 Key',
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 18,
                                  onPressed: enabled
                                      ? () {
                                          Navigator.of(context).pop();
                                          _delete(item.id);
                                        }
                                      : null,
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                onSubmitted: enabled ? (_) => _save() : null,
              ),
            ),
            IconButton(
              tooltip: _obscure ? '显示' : '隐藏',
              onPressed:
                  enabled ? () => setState(() => _obscure = !_obscure) : null,
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _labelController,
          enabled: enabled,
          decoration: const InputDecoration(
            hintText: '备注（可选，填写后保存为新 Key）',
          ),
          onSubmitted: enabled ? (_) => _save() : null,
        ),
        const SizedBox(height: 4),
        Text(
          '仅用于 Cursor SDK；不会写入仓库、偏好或运行日志',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: enabled ? _save : null,
              icon: const Icon(Icons.key, size: 18),
              label: const Text('安全保存'),
            ),
          ],
        ),
        if (_message != null)
          Text(_message!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
