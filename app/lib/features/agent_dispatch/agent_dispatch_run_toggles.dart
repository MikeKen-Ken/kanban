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
          subtitle: const Text('打开后忽略卡片上的引擎、模型和脏工作区等覆盖，只用工作台默认。'),
          value: ignoreCardParams,
          onChanged: enabled ? onIgnoreCardParamsChanged : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('允许脏工作区'),
          subtitle: const Text(
            '默认关闭。关闭时未提交改动会停止批次；代码审查等需要已有文件时可打开。',
          ),
          value: allowDirtyWorkspace,
          onChanged: enabled ? onAllowDirtyWorkspaceChanged : null,
        ),
      ],
    );
  }
}
