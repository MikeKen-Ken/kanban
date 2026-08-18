import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_card_metrics.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_progress.dart';

void main() {
  test('从当前卡片日志解析 token、耗时与引擎信息', () {
    final log = [
      '[09:00:00] [Worker] [信息] ──────── Worker 单卡轮次 1/3 ────────',
      '[09:00:01] [系统] [信息] 当前卡片：Agent 日志 上方',
      '[09:00:02] [Worker] [信息] 本卡覆盖：engine=cursor model=composer-2.5 params=[] cardId=abc',
      '[09:00:10] [Worker] [信息] Cursor run id=run-1 status=completed steps=8 tools=12 elapsedMs=45000',
      '[09:00:11] [Worker] [信息] 本会话 token：input=1200 output=340 total=1540',
    ].join('\n');

    final metrics = AgentDispatchCardMetrics.forCurrentTask(
      log,
      const AgentDispatchProgress(
        running: true,
        currentRound: 1,
        totalCards: 3,
        currentTitle: 'Agent 日志 上方',
      ),
      running: false,
    );

    expect(metrics, isNotNull);
    expect(metrics!.token?.totalTokens, 1540);
    expect(metrics.elapsedSeconds, 45);
    expect(metrics.steps, 8);
    expect(metrics.toolCalls, 12);
    expect(metrics.engine, 'cursor');
    expect(metrics.model, 'composer-2.5');
    expect(metrics.cursorRunId, 'run-1');
  });

  test('运行中按日志时间戳估算耗时', () {
    final now = DateTime(2026, 8, 18, 9, 2, 30);
    final log = [
      '[09:00:00] [Worker] [信息] ──────── Worker 单卡轮次 1/1 ────────',
      '[09:00:01] [系统] [信息] 当前卡片：测试卡片',
      '[09:00:05] [AI] [信息] 助手：处理中',
    ].join('\n');

    final metrics = AgentDispatchCardMetrics.parse(
      log,
      running: true,
      now: now,
    );

    expect(metrics.elapsedSeconds, 150);
  });

  test('统计会话重试次数', () {
    final log = [
      '[09:00:00] [Worker] [信息] ──────── Worker 单卡轮次 1/1 ────────',
      '[09:00:10] [Worker] [警告] Agent 会话暂时失败（第 1/5 次）：network',
      '[09:00:20] [Worker] [警告] Agent 会话暂时失败（第 2/5 次）：timeout',
    ].join('\n');

    final metrics = AgentDispatchCardMetrics.parse(log);
    expect(metrics.retryCount, 2);
  });

  test('格式化耗时与 token 数量', () {
    expect(formatAgentDispatchElapsed(45), '45秒');
    expect(formatAgentDispatchElapsed(75), '1分15秒');
    expect(formatAgentDispatchTokenCount(1540), '1.5K');
    expect(formatAgentDispatchTokenCount(242863), '243K');
  });
}
