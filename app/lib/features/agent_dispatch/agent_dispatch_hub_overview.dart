import 'agent_dispatch_card_metrics.dart';
import 'agent_dispatch_config.dart';
import 'agent_dispatch_progress.dart';

/// 总览条目上运行中项目的补充信息。
class AgentDispatchHubOverview {
  const AgentDispatchHubOverview({
    required this.cardTitle,
    required this.statusLine,
    required this.engineModelLabel,
    required this.modelDetailLabel,
    required this.elapsedLabel,
  });

  final String cardTitle;
  final String statusLine;
  final String engineModelLabel;
  final String modelDetailLabel;
  final String elapsedLabel;

  static AgentDispatchHubOverview running({
    required String liveCardLabel,
    required String currentTitle,
    required String phaseLabel,
    required String engine,
    required String model,
    Map<String, String> modelParams = const {},
    DateTime? batchStartedAt,
    DateTime? cardStartedAt,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final phase = phaseLabel.trim();
    final progress = liveCardLabel.trim();
    final statusParts = [
      'Running',
      if (phase.isNotEmpty) phase,
      if (progress.isNotEmpty) progress,
    ];
    final title = currentTitle.trim();
    final batch = elapsedSecondsSince(batchStartedAt, now: clock);
    final card = elapsedSecondsSince(cardStartedAt, now: clock);
    final elapsedParts = <String>[
      if (batch != null) 'Batch ${formatAgentDispatchElapsed(batch)}',
      if (card != null) 'This card ${formatAgentDispatchElapsed(card)}',
    ];
    return AgentDispatchHubOverview(
      cardTitle: title.isEmpty ? 'Untitled card' : title,
      statusLine: statusParts.join(' · '),
      engineModelLabel: formatAgentDispatchHubEngineModel(
        engine: engine,
        model: model,
      ),
      modelDetailLabel: formatAgentDispatchHubModelDetails(modelParams),
      elapsedLabel: elapsedParts.join(' · '),
    );
  }
}

String formatAgentDispatchHubEngineModel({
  required String engine,
  required String model,
}) {
  final engineLabel = _engineLabel(engine);
  final modelLabel = _modelLabel(model);
  if (engineLabel.isEmpty && modelLabel.isEmpty) return 'Model not recorded';
  if (engineLabel.isEmpty) return modelLabel;
  if (modelLabel.isEmpty) return engineLabel;
  return '$engineLabel · $modelLabel';
}

String _engineLabel(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return '';
  for (final engine in AgentDispatchEngine.values) {
    if (engine.name == name) return engine.label;
  }
  return name;
}

String _modelLabel(String raw) {
  final model = raw.trim();
  if (model.isEmpty || model == '(platform default)') return '';
  return model;
}

String formatAgentDispatchHubModelDetails(Map<String, String> params) {
  if (params.isEmpty) return '';
  final remaining = Map<String, String>.from(params);
  final parts = <String>[];

  String? take(bool Function(String id) match) {
    String? matchedId;
    for (final id in remaining.keys) {
      if (match(id)) {
        matchedId = id;
        break;
      }
    }
    if (matchedId == null) return null;
    final value = remaining.remove(matchedId);
    if (value == null || value.trim().isEmpty) return null;
    return _formatHubParam(matchedId, value);
  }

  final context = take(isAgentDispatchContextParam);
  if (context != null) parts.add(context);
  final fast = take((id) => id == 'fast');
  if (fast != null) parts.add(fast);
  final reasoning = take(isAgentDispatchReasoningParam);
  if (reasoning != null) parts.add(reasoning);
  final leftover = remaining.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in leftover) {
    if (entry.value.trim().isEmpty) continue;
    parts.add(_formatHubParam(entry.key, entry.value));
  }
  return parts.join(' · ');
}

String _formatHubParam(String id, String value) {
  final label = switch (id) {
    'reasoning' ||
    'reasoning_effort' ||
    'model_reasoning_effort' ||
    'effort' ||
    'thinking' =>
      'Reasoning effort',
    'fast' => 'Fast mode',
    _ => isAgentDispatchContextParam(id) ? 'Context' : id,
  };
  return '$label ${_hubParamValue(id, value)}';
}

String _hubParamValue(String id, String value) {
  final trimmed = value.trim();
  if (id == 'fast') {
    return switch (trimmed) {
      'true' => 'On',
      'false' => 'Off',
      _ => trimmed,
    };
  }
  if (trimmed.toLowerCase() == 'default') return 'Default';
  return trimmed;
}
