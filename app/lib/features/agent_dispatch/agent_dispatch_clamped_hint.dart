import 'package:flutter/material.dart';

import 'agent_dispatch_config.dart';
import 'agent_dispatch_model_parameters.dart';

const _expensiveEffort = {
  'high',
  'xhigh',
  'extra_high',
  'very_high',
  'max',
  'maximum',
  'large',
  'xlarge',
  'huge',
};

int? parseAgentDispatchTokenBudget(String value) {
  final match = RegExp(
    r'^(\d+(?:\.\d+)?)\s*(k|m|kb|mb)?$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) return null;
  final amount = double.tryParse(match.group(1)!);
  if (amount == null || !amount.isFinite) return null;
  final unit = (match.group(2) ?? '').toLowerCase();
  if (unit == 'm' || unit == 'mb') return (amount * 1000000).round();
  if (unit == 'k' || unit == 'kb') return (amount * 1000).round();
  return amount.round();
}

bool agentDispatchValueWouldBeClamped(String id, String value) {
  final lower = value.toLowerCase().trim();
  if (lower.isEmpty) return false;
  if (isAgentDispatchContextParam(id)) {
    final tokens = parseAgentDispatchTokenBudget(lower);
    if (tokens != null) return tokens > 64000;
    return _expensiveEffort.contains(lower);
  }
  if (isAgentDispatchReasoningParam(id) || id.toLowerCase().contains('thinking')) {
    return _expensiveEffort.contains(lower);
  }
  return false;
}

/// 开关关闭且当前参数会被压档时给出提醒；否则返回 null。
String? agentDispatchClampedParamsHint({
  required bool allowHighReasoning,
  required Map<String, String> values,
}) {
  if (allowHighReasoning) return null;
  var reasoning = false;
  var context = false;
  for (final entry in values.entries) {
    if (!agentDispatchValueWouldBeClamped(entry.key, entry.value)) continue;
    if (isAgentDispatchContextParam(entry.key)) {
      context = true;
    } else {
      reasoning = true;
    }
  }
  if (!reasoning && !context) return null;
  final parts = <String>[
    if (reasoning) '推理会压到 medium',
    if (context) '上下文会压到 64k',
  ];
  return '开关关闭时${parts.join('，')}。要按所选档位跑，请打开「允许高费用档位」。';
}

class AgentDispatchClampedParamHint extends StatelessWidget {
  const AgentDispatchClampedParamHint({
    super.key,
    required this.allowHighReasoning,
    required this.values,
  });

  final bool allowHighReasoning;
  final Map<String, String> values;

  @override
  Widget build(BuildContext context) {
    final text = agentDispatchClampedParamsHint(
      allowHighReasoning: allowHighReasoning,
      values: values,
    );
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 12,
        ),
      ),
    );
  }
}
