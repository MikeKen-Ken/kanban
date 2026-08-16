import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_dispatch_usage.dart';

/// 用 Key 指纹关联本机账号快照，避免把密钥明文写入偏好。
String agentDispatchUsageKeyFingerprint(String? apiKey) {
  final trimmed = apiKey?.trim() ?? '';
  if (trimmed.isEmpty) return '';
  return sha256.convert(utf8.encode(trimmed)).toString();
}

extension AgentDispatchUsageStore on SharedPreferences {
  static const _key = 'agent_dispatch_usage_snapshot';

  AgentDispatchUsageSnapshot? loadAgentDispatchUsage({
    required String keyFingerprint,
  }) {
    if (keyFingerprint.isEmpty) return null;
    final raw = getString(_key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final storedFingerprint = decoded['keyFingerprint'] as String?;
      if (storedFingerprint != keyFingerprint) return null;
      final snapshot = decoded['snapshot'];
      if (snapshot is! Map<String, dynamic>) return null;
      return AgentDispatchUsageSnapshot.fromJson(snapshot);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAgentDispatchUsage(
    AgentDispatchUsageSnapshot snapshot, {
    required String keyFingerprint,
  }) {
    if (keyFingerprint.isEmpty) return Future.value();
    return setString(
      _key,
      jsonEncode({
        'keyFingerprint': keyFingerprint,
        'snapshot': snapshot.toJson(),
      }),
    );
  }

  Future<void> clearAgentDispatchUsage() => remove(_key);
}
