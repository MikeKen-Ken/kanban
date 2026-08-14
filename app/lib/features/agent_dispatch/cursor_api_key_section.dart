import 'package:flutter/material.dart';

import 'adaptive_popup_menu.dart';
import 'agent_dispatch_field_style.dart';
import 'agent_dispatch_credentials.dart';
import 'agent_dispatch_worker.dart';

/// Cursor SDK 凭据编辑区。输入内容不会写入普通设置或运行日志。
class CursorApiKeySection extends StatefulWidget {
  const CursorApiKeySection({
    super.key,
    required this.enabled,
    this.credentials = const AgentDispatchCredentials(),
    this.workerScriptPath,
    this.onActiveKeyChanged,
  });

  final bool enabled;
  final AgentDispatchCredentials credentials;
  final String? workerScriptPath;
  final Future<void> Function()? onActiveKeyChanged;

  @override
  State<CursorApiKeySection> createState() => _CursorApiKeySectionState();
}

class _CursorApiKeySectionState extends State<CursorApiKeySection> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _hasEnvironmentKey = false;
  List<CursorApiKeySummary> _keys = const [];
  String? _message;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onInputChanged);
    _refreshStatus();
  }

  void _onInputChanged() {
    setState(() {});
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

  Future<String?> _resolveLabel(String apiKey) async {
    try {
      return await resolveCursorApiKeyLabel(
        cursorApiKey: apiKey,
        workerScriptPath: widget.workerScriptPath,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final apiKey = _controller.text.trim();
      final label = await _resolveLabel(apiKey);
      await widget.credentials.saveCursorApiKey(apiKey, label: label);
      _controller.clear();
      await _refreshStatus();
      await widget.onActiveKeyChanged?.call();
      await _refreshStatus();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '已添加 Cursor API Key，可随时从下拉菜单切换';
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
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.credentials.setActiveCursorApiKey(id);
      await _refreshStatus();
      await widget.onActiveKeyChanged?.call();
      await _refreshStatus();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _controller.clear();
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
      await widget.onActiveKeyChanged?.call();
      await _refreshStatus();
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (_activeKey?.id == id) {
          _controller.clear();
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
    _controller.removeListener(_onInputChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _activeKey;
    final available = _keys.isNotEmpty || _hasEnvironmentKey;
    final hasInput = _controller.text.trim().isNotEmpty;
    final showSaveButton = !available || hasInput;
    final enabled = widget.enabled && !_busy;
    final keyMenuWidth = adaptivePopupMenuWidth(
      context: context,
      labels: _keys.map((item) => item.label),
      trailingWidth: kAdaptivePopupMenuKeyTrailingWidth,
    );
    final statusText = available
        ? (_hasEnvironmentKey && active == null ? '已检测到环境变量' : null)
        : '尚未配置';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (statusText != null) ...[
          Row(
            children: [
              Icon(
                available ? Icons.check_circle_outline : Icons.info_outline,
                size: 16,
                color: available
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusText,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
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
                style: agentDispatchFieldTextStyle(theme),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  hintText: available
                      ? '输入新 Key 可添加账号并切换'
                      : '粘贴 Cursor API Key',
                  hintStyle: agentDispatchFieldHintStyle(theme),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    maxWidth: 28,
                    minHeight: 28,
                    maxHeight: 28,
                  ),
                  suffixIcon: PopupMenuButton<String>(
                    tooltip: '展开已保存 Key',
                    enabled: enabled && _keys.isNotEmpty,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints.tightFor(width: keyMenuWidth),
                    iconSize: 20,
                    icon: const Icon(Icons.arrow_drop_down),
                    onSelected: _selectKey,
                    itemBuilder: (context) {
                      final itemWidth =
                          keyMenuWidth - kAdaptivePopupMenuItemPadding;
                      return [
                        for (final item in _keys)
                          PopupMenuItem(
                            value: item.id,
                            child: SizedBox(
                              width: itemWidth,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  child: item.isActive
                                      ? Icon(
                                          Icons.check,
                                          size: 18,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        )
                                      : null,
                                ),
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
                      ];
                    },
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
        Text(
          '仅用于 Cursor SDK；不会写入仓库、偏好或运行日志',
          style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
        ),
        if (showSaveButton) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: enabled ? _save : null,
                icon: const Icon(Icons.key, size: 18),
                label: Text(_keys.isEmpty ? '安全保存' : '添加并切换'),
              ),
            ],
          ),
        ],
        if (_message != null)
          Text(_message!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
