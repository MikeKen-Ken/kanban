import 'package:flutter/material.dart';

/// 工作台运行开关：卡片覆盖与脏工作区策略。
class AgentDispatchRunToggles extends StatelessWidget {
  const AgentDispatchRunToggles({
    super.key,
    required this.ignoreCardParams,
    required this.allowDirtyWorkspace,
    required this.enabled,
    required this.onIgnoreCardParamsChanged,
    required this.onAllowDirtyWorkspaceChanged,
  });

  final bool ignoreCardParams;
  final bool allowDirtyWorkspace;
  final bool enabled;
  final ValueChanged<bool> onIgnoreCardParamsChanged;
  final ValueChanged<bool> onAllowDirtyWorkspaceChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ToggleRow(
          title: '禁止使用卡片参数',
          value: ignoreCardParams,
          enabled: enabled,
          onChanged: onIgnoreCardParamsChanged,
        ),
        _ToggleRow(
          title: '允许脏工作区',
          value: allowDirtyWorkspace,
          enabled: enabled,
          onChanged: onAllowDirtyWorkspaceChanged,
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          ToggleButtons(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 32),
            isSelected: [!value, value],
            onPressed: enabled
                ? (index) {
                    final next = index == 1;
                    if (next != value) onChanged(next);
                  }
                : null,
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('关'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('开'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
