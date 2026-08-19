import 'dart:convert';

const agentInteractionEventPrefix = '@@KANBAN_INTERACTION@@';
final _conversationSnapshotFilePattern = RegExp(
  r'^conversation-snapshot-[a-zA-Z0-9._-]+\.json$',
);

enum AgentInteractionEventType { session, assistant, question, user, snapshot }

class AgentConversationMessage {
  const AgentConversationMessage({required this.role, required this.text});

  final String role;
  final String text;
}

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
  final start = line.indexOf(agentInteractionEventPrefix);
  if (start < 0) return null;
  try {
    final raw = jsonDecode(
      line.substring(start + agentInteractionEventPrefix.length),
    );
    if (raw is! Map) return null;
    final type = switch ('${raw['type'] ?? ''}') {
      'session' => AgentInteractionEventType.session,
      'assistant' => AgentInteractionEventType.assistant,
      'question' => AgentInteractionEventType.question,
      'user' => AgentInteractionEventType.user,
      'snapshot' => AgentInteractionEventType.snapshot,
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

bool isAgentConversationSnapshotFileName(String name) =>
    _conversationSnapshotFilePattern.hasMatch(name.trim());

List<AgentConversationMessage> parseAgentConversationSnapshotMessages(
  Object? raw,
) {
  final payload = raw is Map ? raw['messages'] ?? raw : raw;
  if (payload is! List) return const [];
  final messages = <AgentConversationMessage>[];
  for (final item in payload) {
    if (item is! Map) continue;
    final role = '${item['role'] ?? ''}'.trim();
    final text = '${item['text'] ?? ''}'.trim();
    if (text.isEmpty) continue;
    if (role != 'user' && role != 'assistant') continue;
    messages.add(AgentConversationMessage(role: role, text: text));
  }
  return messages;
}

String appendAgentConversationEvent(
  String? current,
  AgentInteractionEvent event,
) {
  if (event.type == AgentInteractionEventType.snapshot) {
    try {
      return replaceAgentConversationSession(
        current,
        parseAgentConversationSnapshotMessages(jsonDecode(event.text)),
        at: event.at,
      );
    } catch (_) {
      return current ?? '';
    }
  }
  if (event.type == AgentInteractionEventType.user) {
    return appendAgentConversationUserReply(current, event.text);
  }
  if (event.type == AgentInteractionEventType.assistant ||
      event.type == AgentInteractionEventType.question) {
    final coalesced = _coalesceAssistantText(current, event.text);
    if (coalesced != null) return coalesced;
  }
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
    case AgentInteractionEventType.user:
    case AgentInteractionEventType.snapshot:
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

String replaceAgentConversationSession(
  String? current,
  List<AgentConversationMessage> messages, {
  DateTime? at,
}) {
  if (messages.isEmpty) return current ?? '';
  final existing = (current ?? '').trimRight();
  const header = '## 会话';
  final index = existing.lastIndexOf(header);
  final prefix = index >= 0 ? existing.substring(0, index).trimRight() : '';
  final headerLine = index >= 0
      ? existing.substring(index).split('\n').first.trim()
      : '$header ${_formatLocalTime(at ?? DateTime.now())}';
  final buffer = StringBuffer();
  if (prefix.isNotEmpty) {
    buffer
      ..writeln(prefix)
      ..writeln();
  }
  buffer.writeln(headerLine);
  for (final message in messages) {
    buffer
      ..writeln()
      ..writeln(message.role == 'user' ? '### 用户' : '### 助手')
      ..write(message.text.trim());
  }
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

/// 同一轮助手流式快照会越写越长；用较长正文替换上一段，避免只留下开头几句。
String? _coalesceAssistantText(String? current, String nextText) {
  final existing = (current ?? '').trimRight();
  if (existing.isEmpty) return null;
  const marker = '### 助手';
  final index = existing.lastIndexOf(marker);
  if (index < 0) return null;
  final after = existing.substring(index + marker.length);
  if (after.contains('### 用户')) return null;
  final previous = after.trim();
  final next = nextText.trim();
  if (previous.isEmpty || next.isEmpty) return null;
  if (next == previous) return '${existing.trimRight()}\n';
  if (next.startsWith(previous)) {
    return '${existing.substring(0, index)}$marker\n$next\n';
  }
  if (previous.startsWith(next)) {
    return '${existing.trimRight()}\n';
  }
  return null;
}
