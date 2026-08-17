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

  Map<String, AgentDispatchUsageSnapshot> loadAgentDispatchUsageMap() {
    final raw = getString(_key);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      final snapshots = decoded['snapshots'];
      if (snapshots is Map<String, dynamic>) {
        return {
          for (final entry in snapshots.entries)
            if (entry.value is Map<String, dynamic>)
              entry.key: AgentDispatchUsageSnapshot.fromJson(
                entry.value as Map<String, dynamic>,
              ),
        };
      }
      final fingerprint = decoded['keyFingerprint'] as String?;
      final snapshot = decoded['snapshot'];
      if (fingerprint == null ||
          fingerprint.isEmpty ||
          snapshot is! Map<String, dynamic>) {
        return {};
      }
      return {
        fingerprint: AgentDispatchUsageSnapshot.fromJson(snapshot),
      };
    } catch (_) {
      return {};
    }
  }

  AgentDispatchUsageSnapshot? loadAgentDispatchUsage({
    required String keyFingerprint,
  }) {
    if (keyFingerprint.isEmpty) return null;
    return loadAgentDispatchUsageMap()[keyFingerprint];
  }

  Future<void> saveAgentDispatchUsage(
    AgentDispatchUsageSnapshot snapshot, {
    required String keyFingerprint,
  }) {
    if (keyFingerprint.isEmpty) return Future.value();
    final next = {
      ...loadAgentDispatchUsageMap(),
      keyFingerprint: snapshot,
    };
    return setString(
      _key,
      jsonEncode({
        'snapshots': {
          for (final entry in next.entries) entry.key: entry.value.toJson(),
        },
      }),
    );
  }

  Future<void> clearAgentDispatchUsage() => remove(_key);
}
