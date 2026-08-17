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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('禁止使用卡片参数'),
          value: ignoreCardParams,
          onChanged: enabled ? onIgnoreCardParamsChanged : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('允许脏工作区'),
          value: allowDirtyWorkspace,
          onChanged: enabled ? onAllowDirtyWorkspaceChanged : null,
        ),
      ],
    );
  }
}
