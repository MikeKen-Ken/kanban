import 'package:flutter/material.dart';

import 'agent_dispatch_field_style.dart';

class AgentDispatchCardLimitField extends StatelessWidget {
  const AgentDispatchCardLimitField({
    required this.controller,
    required this.useMax,
    required this.enabled,
    required this.onMaxChanged,
    required this.onCountChanged,
    this.errorText,
    super.key,
  });

  final TextEditingController controller;
  final bool useMax;
  final bool enabled;
  final ValueChanged<bool> onMaxChanged;
  final ValueChanged<String> onCountChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('卡片上限', style: theme.textTheme.labelLarge),
        InkWell(
          onTap: enabled ? () => onMaxChanged(!useMax) : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: useMax,
                onChanged:
                    enabled ? (value) => onMaxChanged(value ?? false) : null,
                visualDensity: VisualDensity.compact,
              ),
              const Text('全部（Max）'),
            ],
          ),
        ),
        const Text('张数'),
        SizedBox(
          width: 88,
          child: TextField(
            controller: controller,
            enabled: enabled && !useMax,
            keyboardType: TextInputType.number,
            onChanged: onCountChanged,
            style: agentDispatchFieldTextStyle(theme),
            decoration: InputDecoration(
              hintText: '1',
              hintStyle: agentDispatchFieldHintStyle(theme),
              errorText: errorText,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}
