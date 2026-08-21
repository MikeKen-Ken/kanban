import 'package:flutter/material.dart';

/// 工作台运行开关：卡片覆盖、脏工作区、沙箱与测试策略。
class AgentDispatchRunToggles extends StatelessWidget {
  const AgentDispatchRunToggles({
    super.key,
    required this.ignoreCardParams,
    required this.allowDirtyWorkspace,
    required this.enableSandbox,
    required this.requireTests,
    required this.terminateAfterDispatchTerminal,
    required this.enabled,
    required this.onIgnoreCardParamsChanged,
    required this.onAllowDirtyWorkspaceChanged,
    required this.onEnableSandboxChanged,
    required this.onRequireTestsChanged,
    required this.onTerminateAfterDispatchTerminalChanged,
  });

  final bool ignoreCardParams;
  final bool allowDirtyWorkspace;
  final bool enableSandbox;
  final bool requireTests;
  final bool terminateAfterDispatchTerminal;
  final bool enabled;
  final ValueChanged<bool> onIgnoreCardParamsChanged;
  final ValueChanged<bool> onAllowDirtyWorkspaceChanged;
  final ValueChanged<bool> onEnableSandboxChanged;
  final ValueChanged<bool> onRequireTestsChanged;
  final ValueChanged<bool> onTerminateAfterDispatchTerminalChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Toggle(
          title: 'Allow card parameters',
          value: !ignoreCardParams,
          enabled: enabled,
          onChanged: (allow) => onIgnoreCardParamsChanged(!allow),
        ),
        _Toggle(
          title: 'Allow dirty workspace',
          value: allowDirtyWorkspace,
          enabled: enabled,
          onChanged: onAllowDirtyWorkspaceChanged,
        ),
        _Toggle(
          title: 'Enable sandbox',
          value: enableSandbox,
          enabled: enabled,
          onChanged: onEnableSandboxChanged,
        ),
        _Toggle(
          title: 'Tests required',
          value: requireTests,
          enabled: enabled,
          onChanged: onRequireTestsChanged,
        ),
        _Toggle(
          title: 'End session after finalization',
          value: terminateAfterDispatchTerminal,
          enabled: enabled,
          onChanged: onTerminateAfterDispatchTerminalChanged,
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
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
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: value,
            onChanged: enabled ? (next) => onChanged(next ?? false) : null,
            visualDensity: VisualDensity.compact,
          ),
          Text(title),
        ],
      ),
    );
  }
}
