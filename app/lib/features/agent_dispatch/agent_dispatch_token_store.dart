import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'agent_dispatch_token.dart';

/// 本机按项目保存的会话 token 历史，与对话记录分开，清日志不影响统计。
extension AgentDispatchTokenStore on SharedPreferences {
  static const _key = 'agent_dispatch_token_history';
  static const maxRecords = 500;

  String _storageKey(String? projectId) {
    final id = projectId?.trim();
    if (id == null || id.isEmpty) return _key;
    return '$_key.$id';
  }

  List<AgentDispatchTokenRecord> loadAgentDispatchTokens({String? projectId}) {
    final raw = getString(_storageKey(projectId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>)
            AgentDispatchTokenRecord.fromJson(item)
          else if (item is Map)
            AgentDispatchTokenRecord.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAgentDispatchTokens(
    List<AgentDispatchTokenRecord> records, {
    String? projectId,
  }) {
    final trimmed = records.length > maxRecords
        ? records.sublist(records.length - maxRecords)
        : records;
    return setString(
      _storageKey(projectId),
      jsonEncode([for (final item in trimmed) item.toJson()]),
    );
  }

  Future<void> appendAgentDispatchToken(
    AgentDispatchTokenRecord record, {
    String? projectId,
  }) {
    final next = [...loadAgentDispatchTokens(projectId: projectId), record];
    return saveAgentDispatchTokens(next, projectId: projectId);
  }

  Future<void> clearAgentDispatchTokens({String? projectId}) {
    return remove(_storageKey(projectId));
  }
}
