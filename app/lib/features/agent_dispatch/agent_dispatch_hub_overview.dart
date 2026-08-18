import 'agent_dispatch_card_metrics.dart';
import 'agent_dispatch_config.dart';
import 'agent_dispatch_progress.dart';

/// 总览条目上运行中项目的补充信息。
class AgentDispatchHubOverview {
  const AgentDispatchHubOverview({
    required this.cardTitle,
    required this.statusLine,
    required this.engineModelLabel,
    required this.elapsedLabel,
  });

  final String cardTitle;
  final String statusLine;
  final String engineModelLabel;
  final String elapsedLabel;

  static AgentDispatchHubOverview running({
    required String liveCardLabel,
    required String currentTitle,
    required String phaseLabel,
    required String engine,
    required String model,
    DateTime? batchStartedAt,
    DateTime? cardStartedAt,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final phase = phaseLabel.trim();
    final progress = liveCardLabel.trim();
    final statusParts = [
      '运行中',
      if (phase.isNotEmpty) phase,
      if (progress.isNotEmpty) progress,
    ];
    final title = currentTitle.trim();
    final batch = elapsedSecondsSince(batchStartedAt, now: clock);
    final card = elapsedSecondsSince(cardStartedAt, now: clock);
    final elapsedParts = <String>[
      if (batch != null) '批次 ${formatAgentDispatchElapsed(batch)}',
      if (card != null) '本卡 ${formatAgentDispatchElapsed(card)}',
    ];
    return AgentDispatchHubOverview(
      cardTitle: title.isEmpty ? '暂无卡片标题' : title,
      statusLine: statusParts.join(' · '),
      engineModelLabel: formatAgentDispatchHubEngineModel(
        engine: engine,
        model: model,
      ),
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
  if (engineLabel.isEmpty && modelLabel.isEmpty) return '模型未记录';
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
  if (model.isEmpty || model == '(平台默认)') return '';
  return model;
}
