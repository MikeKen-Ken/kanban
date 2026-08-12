import 'package:flutter/material.dart';

import 'agent_dispatch_config.dart';

class AgentDispatchModelParameters extends StatelessWidget {
  const AgentDispatchModelParameters({
    super.key,
    required this.parameters,
    this.defaultVariant,
    required this.values,
    required this.enabled,
    required this.onChanged,
  });

  final List<AgentDispatchModelParameter> parameters;
  final AgentDispatchModelVariant? defaultVariant;
  final Map<String, String> values;
  final bool enabled;
  final void Function(String id, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final parameter in parameters) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'model-param-${parameter.id}-${values[parameter.id]}',
            ),
            initialValue: _currentValue(parameter),
            decoration: InputDecoration(
              labelText: _parameterLabel(parameter),
            ),
            items: [
              DropdownMenuItem(
                value: 'default',
                child: Text(_defaultLabel(parameter)),
              ),
              for (final option in parameter.options)
                DropdownMenuItem(
                  value: option.value,
                  child: Text(option.displayName ?? option.value),
                ),
            ],
            onChanged: enabled
                ? (value) {
                    if (value != null) onChanged(parameter.id, value);
                  }
                : null,
          ),
        ],
      ],
    );
  }

  String _currentValue(AgentDispatchModelParameter parameter) {
    final current = values[parameter.id] ?? 'default';
    return parameter.values.contains(current) ? current : 'default';
  }

  String _defaultLabel(AgentDispatchModelParameter parameter) {
    final defaultValue = defaultVariant?.params[parameter.id];
    if (defaultValue == null) return 'API 默认（不显式传参）';
    for (final option in parameter.options) {
      if (option.value == defaultValue) {
        return 'API 默认（${option.displayName ?? defaultValue}）';
      }
    }
    return 'API 默认（$defaultValue）';
  }
}

String _parameterLabel(AgentDispatchModelParameter parameter) =>
    switch (parameter.id) {
      'reasoning' ||
      'reasoning_effort' ||
      'model_reasoning_effort' ||
      'effort' ||
      'thinking' =>
        '思考程度（${parameter.displayName ?? parameter.id}）',
      'fast' => '快速模式（${parameter.displayName ?? parameter.id}）',
      _ => parameter.displayName ?? '模型参数（${parameter.id}）',
    };
