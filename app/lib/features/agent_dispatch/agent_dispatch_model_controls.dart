import 'package:flutter/material.dart';

import 'agent_dispatch_config.dart';
import 'agent_dispatch_model_parameters.dart';

class AgentDispatchModelControls extends StatelessWidget {
  const AgentDispatchModelControls({
    super.key,
    required this.models,
    required this.modelId,
    required this.parameters,
    required this.defaultVariant,
    required this.values,
    required this.busy,
    required this.onModelChanged,
    required this.onParameterChanged,
    required this.onRefresh,
  });

  final List<AgentDispatchModelInfo> models;
  final String? modelId;
  final List<AgentDispatchModelParameter> parameters;
  final AgentDispatchModelVariant? defaultVariant;
  final Map<String, String> values;
  final bool busy;
  final ValueChanged<String> onModelChanged;
  final void Function(String id, String value) onParameterChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final model = models.isEmpty
        ? InputDecorator(
            decoration: agentDispatchCompactDropdownDecoration('Model'),
            child: Text(
              'Not loaded yet',
              style: agentDispatchCompactDropdownStyle(context),
            ),
          )
        : DropdownButtonFormField<String>(
            key: ValueKey('model-$modelId'),
            initialValue: models.any((item) => item.id == modelId)
                ? modelId
                : models.first.id,
            isDense: true,
            isExpanded: true,
            style: agentDispatchCompactDropdownStyle(context),
            decoration: agentDispatchCompactDropdownDecoration('Model'),
            items: [
              for (final item in models)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(
                    item.label,
                    style: agentDispatchCompactDropdownStyle(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: busy
                ? null
                : (id) {
                    if (id != null) onModelChanged(id);
                  },
          );
    final options = AgentDispatchModelParameters(
      parameters: parameters,
      defaultVariant: defaultVariant,
      values: values,
      enabled: !busy,
      onChanged: onParameterChanged,
    );
    final refresh = TextButton.icon(
      onPressed: busy ? null : onRefresh,
      icon: const Icon(Icons.refresh, size: 18),
      label: Text(busy ? 'Refreshing…' : 'Refresh models'),
    );

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            model,
            if (parameters.isNotEmpty) ...[
              const SizedBox(height: 8),
              options,
            ],
            Align(alignment: Alignment.centerLeft, child: refresh),
          ],
        );
      }
      return Row(children: [
        Expanded(flex: 2, child: model),
        if (parameters.isNotEmpty) ...[
          const SizedBox(width: 6),
          Expanded(flex: 3, child: options),
        ],
        refresh,
      ]);
    });
  }
}
