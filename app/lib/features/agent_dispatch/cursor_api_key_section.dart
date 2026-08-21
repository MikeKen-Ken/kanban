import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adaptive_popup_menu.dart';
import 'agent_dispatch_field_style.dart';
import 'agent_dispatch_credentials.dart';
import 'agent_dispatch_usage.dart';
import 'agent_dispatch_usage_store.dart';
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
      var keys = await widget.credentials.listStoredCursorApiKeys();
      keys = await _overlayCachedDisplayLabels(keys);
      final environment = widget.credentials.readEnvironmentCursorApiKey();
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _hasEnvironmentKey = environment != null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Failed to read secure storage: $error');
    }
  }

  Future<List<CursorApiKeySummary>> _overlayCachedDisplayLabels(
    List<CursorApiKeySummary> keys,
  ) async {
    if (keys.isEmpty) return keys;
    final prefs = await SharedPreferences.getInstance();
    final cache = prefs.loadAgentDispatchUsageMap();
    if (cache.isEmpty) return keys;
    final next = <CursorApiKeySummary>[];
    for (final item in keys) {
      final value =
          await widget.credentials.readStoredCursorApiKeyById(item.id);
      final usage = cache[agentDispatchUsageKeyFingerprint(value)];
      final label = cursorApiKeyMenuLabel(
        storedLabel: item.label,
        usage: usage,
      );
      if (label != item.label) {
        await widget.credentials.updateCursorApiKeyLabel(item.id, label);
      }
      next.add(
        CursorApiKeySummary(
          id: item.id,
          label: label,
          isActive: item.isActive,
        ),
      );
    }
    return next;
  }

  Future<void> _hydrateMissingEmails() async {
    final prefs = await SharedPreferences.getInstance();
    var changed = false;
    for (final item in [..._keys]) {
      final value =
          await widget.credentials.readStoredCursorApiKeyById(item.id);
      final fingerprint = agentDispatchUsageKeyFingerprint(value);
      final cached = prefs.loadAgentDispatchUsage(keyFingerprint: fingerprint);
      if (cached != null && cached.hasUserEmail) continue;
      try {
        final snapshot = await fetchAgentDispatchUsage(
          cursorApiKey: value,
          workerScriptPath: widget.workerScriptPath,
        );
        if (fingerprint.isNotEmpty) {
          await prefs.saveAgentDispatchUsage(
            snapshot,
            keyFingerprint: fingerprint,
          );
        }
        final label = snapshot.displayLabel;
        if (label != null) {
          await widget.credentials.updateCursorApiKeyLabel(item.id, label);
          changed = true;
        }
      } catch (_) {}
    }
    if (changed) {
      await _refreshStatus();
    }
  }

  Future<void> _openSavedKeysMenu(BuildContext buttonContext) async {
    if (!widget.enabled || _busy || _keys.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _hydrateMissingEmails();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || _keys.isEmpty) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(buttonContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final theme = Theme.of(context);
    final keyMenuWidth = adaptivePopupMenuWidth(
      context: context,
      labels: _keys.map((item) => item.label),
      trailingWidth: kAdaptivePopupMenuKeyTrailingWidth,
    );
    final itemWidth = keyMenuWidth - kAdaptivePopupMenuItemPadding;
    final selected = await showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints.tightFor(width: keyMenuWidth),
      items: [
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
                            color: theme.colorScheme.primary,
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
                    tooltip: 'Delete this Key',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    onPressed: () {
                      Navigator.of(context).pop();
                      _delete(item.id);
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    if (selected != null) {
      await _selectKey(selected);
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
        _message =
            'Cursor API Key added; you can switch it from the dropdown at any time';
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
        _message = 'Active Key switched';
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
            ? 'Key deleted; the CURSOR_API_KEY environment variable will still be used'
            : 'Cursor API Key deleted';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Delete failed: $error';
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
    final statusText = available
        ? (_hasEnvironmentKey && active == null
            ? 'Environment variable detected'
            : null)
        : 'Not configured';
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
                      ? 'Enter a new Key to add and switch accounts'
                      : 'Paste Cursor API Key',
                  hintStyle: agentDispatchFieldHintStyle(theme),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    maxWidth: 28,
                    minHeight: 28,
                    maxHeight: 28,
                  ),
                  suffixIcon: Builder(
                    builder: (buttonContext) {
                      return IconButton(
                        tooltip: 'Expand saved Keys',
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        onPressed: enabled && _keys.isNotEmpty
                            ? () => _openSavedKeysMenu(buttonContext)
                            : null,
                        icon: const Icon(Icons.arrow_drop_down),
                      );
                    },
                  ),
                ),
                onSubmitted: enabled ? (_) => _save() : null,
              ),
            ),
            IconButton(
              tooltip: _obscure ? 'Show' : 'Hide',
              onPressed:
                  enabled ? () => setState(() => _obscure = !_obscure) : null,
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            ),
          ],
        ),
        if (showSaveButton) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: enabled ? _save : null,
                icon: const Icon(Icons.key, size: 18),
                label: Text(_keys.isEmpty ? 'Save securely' : 'Add and switch'),
              ),
            ],
          ),
        ],
        if (_message != null) Text(_message!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
