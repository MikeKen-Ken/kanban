import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_usage.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_usage_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('同一 Key 指纹可回读账号快照，更换 Key 后缓存失效', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const snapshot = AgentDispatchUsageSnapshot(
      userEmail: 'user@example.com',
      apiKeyName: '主账号',
    );
    final fingerprint = agentDispatchUsageKeyFingerprint('cursor-secret');

    await prefs.saveAgentDispatchUsage(
      snapshot,
      keyFingerprint: fingerprint,
    );

    final cached = prefs.loadAgentDispatchUsage(keyFingerprint: fingerprint);
    expect(cached?.userEmail, 'user@example.com');
    expect(cached?.apiKeyName, '主账号');
    expect(snapshot.displayLabel, 'user@example.com');
    expect(
      const AgentDispatchUsageSnapshot(apiKeyName: '主账号').displayLabel,
      '主账号',
    );
    expect(
      prefs.loadAgentDispatchUsage(
        keyFingerprint: agentDispatchUsageKeyFingerprint('other-secret'),
      ),
      isNull,
    );
  });

  test('空 Key 不读写账号缓存', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.saveAgentDispatchUsage(
      const AgentDispatchUsageSnapshot(userEmail: 'user@example.com'),
      keyFingerprint: agentDispatchUsageKeyFingerprint('  '),
    );

    expect(prefs.loadAgentDispatchUsage(keyFingerprint: ''), isNull);
    expect(agentDispatchUsageKeyFingerprint(null), isEmpty);
  });
}
