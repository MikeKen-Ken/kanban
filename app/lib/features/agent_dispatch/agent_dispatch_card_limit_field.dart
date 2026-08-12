import 'package:flutter/material.dart';

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
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('卡片上限', style: Theme.of(context).textTheme.labelLarge),
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
            decoration: InputDecoration(
              hintText: '1',
              errorText: errorText,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}
