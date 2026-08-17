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

  test('解析含缓存字段的日志，口径与 Dashboard 一致', () {
    final record = AgentDispatchTokenRecord.tryParse(
      '本会话 token：input=16332 output=2695 cacheRead=223836 cacheWrite=0 total=242863',
      at: DateTime(2026, 8, 14, 16),
    );
    expect(record, isNotNull);
    expect(record!.inputTokens, 16332);
    expect(record.outputTokens, 2695);
    expect(record.cacheReadTokens, 223836);
    expect(record.cacheWriteTokens, 0);
    expect(record.totalTokens, 242863);
  });

  test('纠正 SDK 把 Cache Read 同时计入 input 与 total 的重复累计', () {
    final record = AgentDispatchTokenRecord.fromUsage(
      at: DateTime(2026, 8, 14, 16),
      inputTokens: 240168,
      outputTokens: 2695,
      cacheReadTokens: 223836,
      cacheWriteTokens: 0,
      totalTokens: 466699,
    );
    expect(record.inputTokens, 16332);
    expect(record.outputTokens, 2695);
    expect(record.cacheReadTokens, 223836);
    expect(record.totalTokens, 242863);
  });

  test('SDK 已按未缓存 input 上报时保持 Dashboard 分项', () {
    final record = AgentDispatchTokenRecord.fromUsage(
      at: DateTime(2026, 8, 14, 16),
      inputTokens: 16332,
      outputTokens: 2695,
      cacheReadTokens: 223836,
      cacheWriteTokens: 0,
      totalTokens: 242863,
    );
    expect(record.inputTokens, 16332);
    expect(record.cacheReadTokens, 223836);
    expect(record.totalTokens, 242863);
  });

  test('旧日志无缓存字段时按重复累计拆出 Cache Read', () {
    final record = AgentDispatchTokenRecord.tryParse(
      '本会话 token：input=240168 output=2695 total=466699',
      at: DateTime(2026, 8, 14, 16),
    );
    expect(record!.inputTokens, 16332);
    expect(record.cacheReadTokens, 223836);
    expect(record.totalTokens, 242863);
  });

  test('官网 Dashboard 分项已拆开时不再改写 Input 与 Total', () {
    final record = AgentDispatchTokenRecord.fromUsage(
      at: DateTime(2026, 8, 16, 15),
      inputTokens: 204287,
      outputTokens: 1540,
      cacheReadTokens: 215040,
      cacheWriteTokens: 0,
      totalTokens: 420867,
    );
    expect(record.inputTokens, 204287);
    expect(record.outputTokens, 1540);
    expect(record.cacheReadTokens, 215040);
    expect(record.cacheWriteTokens, 0);
    expect(record.totalTokens, 420867);
    expect(
      record.inputTokens +
          record.cacheReadTokens +
          record.cacheWriteTokens +
          record.outputTokens,
      record.totalTokens,
    );
  });

  test('读取旧持久化记录时同样纠正重复累计', () {
    final record = AgentDispatchTokenRecord.fromJson({
      'at': '2026-08-14T08:00:00.000Z',
      'input': 240168,
      'output': 2695,
      'total': 466699,
    });
    expect(record.inputTokens, 16332);
    expect(record.totalTokens, 242863);
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

    expect(stats.lastDays(3).totalTokens, 700);
    expect(stats.lastHours(1).sessionCount, 0);
    expect(
      AgentDispatchTokenStats(
        now: DateTime(2026, 8, 14, 12, 30),
        records: stats.records,
      ).lastHours(1).totalTokens,
      150,
    );
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

    await prefs.appendAgentDispatchToken(record, projectId: 'p2');
    await prefs.clearAgentDispatchTokens(projectId: 'p1');
    expect(prefs.loadAgentDispatchTokens(projectId: 'p1'), isEmpty);
    expect(prefs.loadAgentDispatchTokens(projectId: 'p2').single.totalTokens, 30);
  });

  test('加载旧项目历史时纠正重复累计后再汇总', () async {
    SharedPreferences.setMockInitialValues({
      'agent_dispatch_token_history.p1':
          '[{"at":"2026-08-14T08:00:00.000Z","input":240168,"output":2695,"total":466699}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final records = prefs.loadAgentDispatchTokens(projectId: 'p1');
    final stats = AgentDispatchTokenStats(
      records: records,
      now: DateTime(2026, 8, 14, 18),
    );
    expect(stats.totalInput, 16332);
    expect(stats.totalCacheRead, 223836);
    expect(stats.totalOutput, 2695);
    expect(stats.totalTokens, 242863);
  });
}
