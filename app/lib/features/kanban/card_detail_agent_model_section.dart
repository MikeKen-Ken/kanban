import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../agent_dispatch/agent_dispatch_config.dart';
import '../agent_dispatch/agent_dispatch_model_catalog_store.dart';
import '../agent_dispatch/agent_dispatch_model_parameters.dart';

/// 卡片详情中的紧凑 Agent 覆盖选择：默认全部不选，运行时沿用工作台。
class CardDetailAgentModelSection extends StatefulWidget {
  const CardDetailAgentModelSection({
    super.key,
    required this.agentEngine,
    required this.agentModelId,
    required this.agentModelParamValues,
    required this.agentAllowDirtyWorkspace,
    required this.agentEnableSandbox,
    required this.onChanged,
  });

  final String? agentEngine;
  final String? agentModelId;
  final Map<String, String> agentModelParamValues;
  final bool? agentAllowDirtyWorkspace;
  final bool? agentEnableSandbox;
  final void Function({
    String? agentEngine,
    String? agentModelId,
    Map<String, String> agentModelParamValues,
    bool? agentAllowDirtyWorkspace,
    bool? agentEnableSandbox,
  }) onChanged;

  @override
  State<CardDetailAgentModelSection> createState() =>
      _CardDetailAgentModelSectionState();
}

class _CardDetailAgentModelSectionState
    extends State<CardDetailAgentModelSection> {
  static const _inherit = '';
  static const _omit = Object();

  List<AgentDispatchModelInfo> _models = const [];

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void didUpdateWidget(CardDetailAgentModelSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agentEngine != widget.agentEngine) _loadModels();
  }

  Future<void> _loadModels() async {
    final prefs = await SharedPreferences.getInstance();
    final engine = AgentDispatchEngine.fromName(widget.agentEngine);
    if (!mounted) return;
    setState(() {
      _models = prefs.loadAgentDispatchModelCatalog(engine: engine);
    });
  }

  AgentDispatchModelInfo? get _selectedModel {
    final id = widget.agentModelId;
    if (id == null) return null;
    for (final model in _models) {
      if (model.id == id) return model;
    }
    return null;
  }

  bool get _isCodex => widget.agentEngine == AgentDispatchEngine.codex.name;

  AgentDispatchModelParameter? _param(bool Function(String id) match) {
    final parameters = _selectedModel?.parameters ?? const [];
    for (final parameter in parameters) {
      if (match(parameter.id)) return parameter;
    }
    if (_selectedModel != null) return null;
    for (final model in _models) {
      for (final parameter in model.parameters) {
        if (match(parameter.id)) return parameter;
      }
    }
    return null;
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final known = items.any((item) => item.value == value);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11);
    return Expanded(
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: known ? value : _inherit,
        isDense: true,
        isExpanded: true,
        style: style,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          labelStyle: const TextStyle(fontSize: 11),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  List<DropdownMenuItem<String>> _items({
    required List<({String value, String label})> options,
  }) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11);
    return [
      DropdownMenuItem(
        value: _inherit,
        child: Text('默认', style: style, overflow: TextOverflow.ellipsis),
      ),
      for (final option in options)
        DropdownMenuItem(
          value: option.value,
          child: Text(
            option.label,
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
  }

  void _emit({
    Object? agentEngine = _omit,
    Object? agentModelId = _omit,
    Map<String, String>? agentModelParamValues,
    Object? agentAllowDirtyWorkspace = _omit,
    Object? agentEnableSandbox = _omit,
  }) {
    widget.onChanged(
      agentEngine: identical(agentEngine, _omit)
          ? widget.agentEngine
          : agentEngine as String?,
      agentModelId: identical(agentModelId, _omit)
          ? widget.agentModelId
          : agentModelId as String?,
      agentModelParamValues:
          agentModelParamValues ?? widget.agentModelParamValues,
      agentAllowDirtyWorkspace: identical(agentAllowDirtyWorkspace, _omit)
          ? widget.agentAllowDirtyWorkspace
          : agentAllowDirtyWorkspace as bool?,
      agentEnableSandbox: identical(agentEnableSandbox, _omit)
          ? widget.agentEnableSandbox
          : agentEnableSandbox as bool?,
    );
  }

  void _onEngine(String? value) {
    if (value == null || value == _inherit) {
      _emit(agentEngine: null);
      return;
    }
    if (value == AgentDispatchEngine.codex.name) {
      _emit(
        agentEngine: value,
        agentModelId: null,
        agentModelParamValues: const {},
      );
      return;
    }
    _emit(agentEngine: value);
  }

  void _onModel(String? value) {
    if (value == null || value == _inherit) {
      _emit(agentModelId: null, agentModelParamValues: const {});
      return;
    }
    AgentDispatchModelInfo? selected;
    for (final model in _models) {
      if (model.id == value) {
        selected = model;
        break;
      }
    }
    final allowed = {
      for (final parameter in withAgentDispatchContextParameter(
        selected?.parameters ?? const [],
      ))
        parameter.id,
    };
    final nextParams = <String, String>{
      for (final entry in widget.agentModelParamValues.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
    _emit(agentModelId: value, agentModelParamValues: nextParams);
  }

  void _onParam(String id, String? value) {
    final next = Map<String, String>.from(widget.agentModelParamValues);
    if (value == null || value == _inherit) {
      next.remove(id);
    } else {
      next[id] = value;
    }
    _emit(agentModelParamValues: next);
  }

  @override
  Widget build(BuildContext context) {
    final fast = _isCodex ? null : _param((id) => id == 'fast');
    final reasoning = _param(isAgentDispatchReasoningParam);
    final contextParam =
        _param(isAgentDispatchContextParam) ?? agentDispatchContextParameter;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              _dropdown(
                label: 'AI 平台',
                value: widget.agentEngine ?? _inherit,
                items: _items(
                  options: [
                    for (final engine in AgentDispatchEngine.values)
                      (value: engine.name, label: engine.label),
                  ],
                ),
                onChanged: _onEngine,
              ),
              const SizedBox(width: 6),
              _dropdown(
                label: '模型',
                value: widget.agentModelId ?? _inherit,
                items: _items(
                  options: [
                    for (final model in _models)
                      (value: model.id, label: model.label),
                  ],
                ),
                onChanged: _onModel,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (fast != null) ...[
                _dropdown(
                  label: 'Fast',
                  value: widget.agentModelParamValues[fast.id] ?? _inherit,
                  items: _items(
                    options: [
                      for (final option in fast.options)
                        (
                          value: option.value,
                          label: option.displayName ?? option.value,
                        ),
                    ],
                  ),
                  onChanged: (value) => _onParam(fast.id, value),
                ),
                const SizedBox(width: 6),
              ],
              if (reasoning != null) ...[
                _dropdown(
                  label: '推理程度',
                  value:
                      widget.agentModelParamValues[reasoning.id] ?? _inherit,
                  items: _items(
                    options: [
                      for (final option in reasoning.options)
                        (
                          value: option.value,
                          label: option.displayName ?? option.value,
                        ),
                    ],
                  ),
                  onChanged: (value) => _onParam(reasoning.id, value),
                ),
                const SizedBox(width: 6),
              ],
              _dropdown(
                label: '上下文',
                value:
                    widget.agentModelParamValues[contextParam.id] ?? _inherit,
                items: _items(
                  options: [
                    for (final option in contextParam.options)
                      (
                        value: option.value,
                        label: option.displayName ?? option.value,
                      ),
                  ],
                ),
                onChanged: (value) => _onParam(contextParam.id, value),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('允许脏工作区'),
            subtitle: Text(
              widget.agentAllowDirtyWorkspace == true
                  ? '已覆盖工作台。本卡在未提交改动的工作区也能领取。'
                  : '关闭则沿用工作台（默认未提交改动会失败）。打开后仅本卡允许脏工作区。',
            ),
            value: widget.agentAllowDirtyWorkspace == true,
            onChanged: (value) => _emit(
              agentAllowDirtyWorkspace: value ? true : null,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('开沙箱'),
            subtitle: Text(
              widget.agentEnableSandbox == true
                  ? '已覆盖工作台。本卡运行 Cursor SDK 时启用沙箱。'
                  : '关闭则沿用工作台（默认关闭沙箱）。打开后仅本卡启用沙箱。',
            ),
            value: widget.agentEnableSandbox == true,
            onChanged: (value) => _emit(
              agentEnableSandbox: value ? true : null,
            ),
          ),
        ],
      ),
    );
  }
}
