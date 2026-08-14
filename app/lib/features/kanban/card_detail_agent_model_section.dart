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
    required this.onChanged,
  });

  final String? agentEngine;
  final String? agentModelId;
  final Map<String, String> agentModelParamValues;
  final void Function({
    String? agentEngine,
    String? agentModelId,
    Map<String, String> agentModelParamValues,
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
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _models = prefs.loadAgentDispatchModelCatalog();
      });
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
    return SizedBox(
      width: 168,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: known ? value : _inherit,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  List<DropdownMenuItem<String>> _items({
    required List<({String value, String label})> options,
  }) =>
      [
        const DropdownMenuItem(value: _inherit, child: Text('默认（工作台）')),
        for (final option in options)
          DropdownMenuItem(value: option.value, child: Text(option.label)),
      ];

  void _emit({
    Object? agentEngine = _omit,
    Object? agentModelId = _omit,
    Map<String, String>? agentModelParamValues,
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
      for (final parameter in selected?.parameters ?? const []) parameter.id,
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
    final reasoning = _isCodex
        ? null
        : _param(isAgentDispatchReasoningParam);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
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
          if (!_isCodex)
            _dropdown(
              label: '模型',
              value: widget.agentModelId ?? _inherit,
              items: _items(
                options: [
                  for (final model in _models)
                    (
                      value: model.id,
                      label: model.displayName == null ||
                              model.displayName == model.id
                          ? model.id
                          : '${model.displayName}（${model.id}）',
                    ),
                ],
              ),
              onChanged: _onModel,
            ),
          if (fast != null)
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
          if (reasoning != null)
            _dropdown(
              label: '推理程度',
              value: widget.agentModelParamValues[reasoning.id] ?? _inherit,
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
        ],
      ),
    );
  }
}
