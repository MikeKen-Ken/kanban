import 'package:flutter/material.dart';

import 'agent_dispatch_config.dart';

InputDecoration agentDispatchCompactDropdownDecoration(String label) =>
    InputDecoration(
      labelText: label,
      isDense: true,
      labelStyle: const TextStyle(fontSize: 11),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    );

TextStyle? agentDispatchCompactDropdownStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11);

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
    final style = agentDispatchCompactDropdownStyle(context);
    return Row(
      children: [
        for (var i = 0; i < parameters.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey(
                'model-param-${parameters[i].id}-${values[parameters[i].id]}',
              ),
              initialValue: _currentValue(parameters[i]),
              isDense: true,
              isExpanded: true,
              style: style,
              decoration: agentDispatchCompactDropdownDecoration(
                _parameterLabel(parameters[i]),
              ),
              items: [
                DropdownMenuItem(
                  value: 'default',
                  child: Text(
                    _defaultLabel(parameters[i]),
                    style: style,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final option in parameters[i].options)
                  DropdownMenuItem(
                    value: option.value,
                    child: Text(
                      option.displayName ?? option.value,
                      style: style,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: enabled
                  ? (value) {
                      if (value != null) onChanged(parameters[i].id, value);
                    }
                  : null,
            ),
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
    if (defaultValue == null) return 'API default (parameter omitted)';
    for (final option in parameter.options) {
      if (option.value == defaultValue) {
        return 'API default (${option.displayName ?? defaultValue})';
      }
    }
    return 'API default ($defaultValue)';
  }
}

String _parameterLabel(AgentDispatchModelParameter parameter) =>
    switch (parameter.id) {
      'reasoning' ||
      'reasoning_effort' ||
      'model_reasoning_effort' ||
      'effort' ||
      'thinking' =>
        'Reasoning effort',
      'fast' => 'Fast mode',
      _ => isAgentDispatchContextParam(parameter.id)
          ? 'Context'
          : (parameter.displayName ?? parameter.id),
    };

/// 只保留当前模型目录里存在的参数项。
Map<String, String> filterAgentDispatchModelParamValues(
  Map<String, String> values,
  List<AgentDispatchModelParameter> parameters,
) {
  if (parameters.isEmpty) return Map<String, String>.from(values);
  if (values.isEmpty) return const {};
  final allowed = {for (final parameter in parameters) parameter.id};
  return {
    for (final entry in values.entries)
      if (allowed.contains(entry.key)) entry.key: entry.value,
  };
}

/// 快速模式关闭、思考程度 Medium；目录尚未加载时仍带上常见参数名。
Map<String, String> preferredAgentDispatchModelParamValues(
  List<AgentDispatchModelParameter> parameters,
) {
  if (parameters.isEmpty) {
    return Map<String, String>.from(
      AgentDispatchSettingsDefaults.modelParamValues,
    );
  }
  final values = <String, String>{};
  for (final parameter in parameters) {
    if (parameter.id == 'fast' && parameter.values.contains('false')) {
      values['fast'] = 'false';
    }
    if (isAgentDispatchReasoningParam(parameter.id) &&
        parameter.values.contains('medium')) {
      values[parameter.id] = 'medium';
    }
    if (isAgentDispatchContextParam(parameter.id) &&
        parameter.values.contains('64k')) {
      values[parameter.id] = '64k';
    }
  }
  return values;
}

/// True when [values] still match the catalog's preferred seed, so a refresh
/// may replace them. Omitting context after choosing API default is a
/// customization and must not be treated as stock.
bool isStockAgentDispatchModelParamValues(
  Map<String, String> values,
  List<AgentDispatchModelParameter> parameters,
) {
  if (values.isEmpty) return true;
  final preferred = preferredAgentDispatchModelParamValues(parameters);
  if (values.length != preferred.length) return false;
  return preferred.entries
      .every((entry) => values[entry.key] == entry.value);
}

/// 与 [AgentDispatchSettings] 的字面量默认保持一致，避免 config 循环引用。
class AgentDispatchSettingsDefaults {
  static const modelParamValues = {
    'fast': 'false',
    'reasoning_effort': 'medium',
  };
}
