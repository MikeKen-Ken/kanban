import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_token.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('从会话日志解析 token 用量', () {
    final record = AgentDispatchTokenRecord.tryParse(
      '本会话 token：input=12 output=34 total=46',
      at: DateTime(2026, 8, 14, 9),
    );
    expect(record, isNotNull);
    expect(record!.inputTokens, 12);
    expect(record.outputTokens, 34);
    expect(record.totalTokens, 46);
  });

  test('无关日志不解析为用量', () {
    expect(AgentDispatchTokenRecord.tryParse('助手：已完成'), isNull);
  });

  test('按日汇总总量、每次平均与近 7 天柱', () {
    final now = DateTime(2026, 8, 14, 18);
    final stats = AgentDispatchTokenStats(
      now: now,
      records: [
        AgentDispatchTokenRecord(
          at: DateTime(2026, 8, 13, 10),
          inputTokens: 100,
          outputTokens: 50,
          totalTokens: 150,
        ),
        AgentDispatchTokenRecord(
          at: DateTime(2026, 8, 14, 11),
          inputTokens: 300,
          outputTokens: 100,
          totalTokens: 400,
        ),
        AgentDispatchTokenRecord(
          at: DateTime(2026, 8, 14, 12),
          inputTokens: 100,
          outputTokens: 50,
          totalTokens: 150,
        ),
      ],
    );

    expect(stats.sessionCount, 3);
    expect(stats.totalTokens, 700);
    expect(stats.averageTotal, closeTo(700 / 3, 0.01));
    expect(stats.today.sessionCount, 2);
    expect(stats.today.totalTokens, 550);
    expect(stats.lastDays(7).totalTokens, 700);

    final daily = stats.daily(7);
    expect(daily.length, 7);
    expect(daily.last.totalTokens, 550);
    expect(daily.last.sessions, 2);
    expect(daily[daily.length - 2].totalTokens, 150);
  });

  test('token 历史按项目持久化且与日志分离', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final record = AgentDispatchTokenRecord(
      at: DateTime.utc(2026, 8, 14, 1),
      inputTokens: 10,
      outputTokens: 20,
      totalTokens: 30,
    );

    await prefs.appendAgentDispatchToken(record, projectId: 'p1');
    expect(prefs.loadAgentDispatchTokens(projectId: 'p1').single.totalTokens, 30);
    expect(prefs.loadAgentDispatchTokens(projectId: 'p2'), isEmpty);
  });
}
