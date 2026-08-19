import 'dart:convert';

const agentInteractionEventPrefix = '@@KANBAN_INTERACTION@@';

enum AgentInteractionEventType { session, assistant, question }

class AgentInteractionEvent {
  const AgentInteractionEvent({
    required this.type,
    required this.cardId,
    required this.sessionId,
    required this.text,
    required this.at,
    this.projectId,
    this.requestId,
  });

  final AgentInteractionEventType type;
  final String cardId;
  final String sessionId;
  final String text;
  final DateTime at;
  final String? projectId;
  final String? requestId;

  bool get awaitsReply =>
      type == AgentInteractionEventType.question &&
      requestId != null &&
      requestId!.isNotEmpty;
}

AgentInteractionEvent? parseAgentInteractionEvent(String line) {
  if (!line.startsWith(agentInteractionEventPrefix)) return null;
  try {
    final raw = jsonDecode(line.substring(agentInteractionEventPrefix.length));
    if (raw is! Map) return null;
    final type = switch ('${raw['type'] ?? ''}') {
      'session' => AgentInteractionEventType.session,
      'assistant' => AgentInteractionEventType.assistant,
      'question' => AgentInteractionEventType.question,
      _ => null,
    };
    final cardId = '${raw['cardId'] ?? ''}'.trim();
    final sessionId = '${raw['sessionId'] ?? ''}'.trim();
    final text = '${raw['text'] ?? ''}'.trim();
    if (type == null || cardId.isEmpty || sessionId.isEmpty || text.isEmpty) {
      return null;
    }
    return AgentInteractionEvent(
      type: type,
      cardId: cardId,
      sessionId: sessionId,
      text: text,
      at: DateTime.tryParse('${raw['at'] ?? ''}') ?? DateTime.now(),
      projectId: _optionalString(raw['projectId']),
      requestId: _optionalString(raw['requestId']),
    );
  } catch (_) {
    return null;
  }
}

String appendAgentConversationEvent(
  String? current,
  AgentInteractionEvent event,
) {
  final buffer = StringBuffer((current ?? '').trimRight());
  if (buffer.isNotEmpty) buffer.write('\n\n');
  switch (event.type) {
    case AgentInteractionEventType.session:
      buffer
        ..writeln('## 会话 ${_formatLocalTime(event.at)}')
        ..writeln()
        ..writeln('### 用户')
        ..write(event.text);
      break;
    case AgentInteractionEventType.assistant:
    case AgentInteractionEventType.question:
      buffer
        ..writeln('### 助手')
        ..write(event.text);
      break;
  }
  return '${buffer.toString().trimRight()}\n';
}

String appendAgentConversationUserReply(String? current, String text) {
  final normalized = text.trim();
  if (normalized.isEmpty) return current ?? '';
  final buffer = StringBuffer((current ?? '').trimRight());
  if (buffer.isNotEmpty) buffer.write('\n\n');
  buffer
    ..writeln('### 用户')
    ..write(normalized);
  return '${buffer.toString().trimRight()}\n';
}

String _formatLocalTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String? _optionalString(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? null : text;
}
