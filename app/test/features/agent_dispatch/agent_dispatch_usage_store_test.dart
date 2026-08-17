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
      cursorApiKeyMenuLabel(storedLabel: '主账号', usage: snapshot),
      'user@example.com',
    );
    expect(
      const AgentDispatchUsageSnapshot(apiKeyName: '主账号').displayLabel,
      '主账号',
    );
    expect(
      cursorApiKeyMenuLabel(
        storedLabel: '主账号',
        usage: const AgentDispatchUsageSnapshot(apiKeyName: '主账号'),
      ),
      '主账号',
    );
    expect(
      cursorApiKeyMenuLabel(storedLabel: '主账号', usage: null),
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

  test('切换 Key 后仍保留其它账号的用量快照', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = agentDispatchUsageKeyFingerprint('first-key');
    final second = agentDispatchUsageKeyFingerprint('second-key');

    await prefs.saveAgentDispatchUsage(
      const AgentDispatchUsageSnapshot(
        userEmail: 'one@example.com',
        apiKeyName: '主账号',
      ),
      keyFingerprint: first,
    );
    await prefs.saveAgentDispatchUsage(
      const AgentDispatchUsageSnapshot(
        userEmail: 'two@example.com',
        apiKeyName: '备用',
      ),
      keyFingerprint: second,
    );

    expect(
      prefs.loadAgentDispatchUsage(keyFingerprint: first)?.userEmail,
      'one@example.com',
    );
    expect(
      prefs.loadAgentDispatchUsage(keyFingerprint: second)?.userEmail,
      'two@example.com',
    );
  });

  test('可读取旧版单条用量缓存', () async {
    SharedPreferences.setMockInitialValues({
      'agent_dispatch_usage_snapshot':
          '{"keyFingerprint":"${agentDispatchUsageKeyFingerprint('legacy-key')}","snapshot":{"userEmail":"legacy@example.com","apiKeyName":"旧Key"}}',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs
          .loadAgentDispatchUsage(
            keyFingerprint: agentDispatchUsageKeyFingerprint('legacy-key'),
          )
          ?.userEmail,
      'legacy@example.com',
    );
  });
}
