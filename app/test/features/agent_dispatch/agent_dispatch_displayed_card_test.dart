import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_displayed_card.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_log.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_progress.dart';

void main() {
  const log = '''
[09:00:00] [系统] [信息] 启动批次
[09:00:01] [Worker] [信息] ──────── Worker 单卡轮次 1/2 ────────
[09:00:02] [系统] [信息] 当前卡片：任务甲
[09:00:03] [系统] [信息] 当前任务：实现筛选
[09:00:04] [Worker] [信息] 本卡覆盖：engine=cursor model=composer-2.5 params=[] cardId=a
[09:00:05] [AI] [信息] 助手：完成甲
[09:00:06] [Worker] [信息] ──────── Worker 单卡轮次 2/2 ────────
[09:00:07] [系统] [信息] 当前卡片：任务乙
[09:00:08] [系统] [信息] 当前任务：展示进度
[09:00:09] [Worker] [信息] Worker 正在实施
''';

  final tasks = AgentDispatchLogTasks.parse(log.split('\n'));
  const live = AgentDispatchProgress(
    running: true,
    currentRound: 2,
    totalCards: 2,
    currentTitle: '任务乙',
    currentDetail: '展示进度',
    phaseLabel: '实施',
  );

  test('未筛选时展示正在运行的卡片', () {
    final displayed = AgentDispatchDisplayedCard.resolve(
      fullLog: log,
      tasks: tasks,
      selectedOrdinal: null,
      live: live,
      batchRunning: true,
    );

    expect(displayed.progress.currentTitle, '任务乙');
    expect(displayed.running, isTrue);
    expect(displayed.canJumpToRunning, isTrue);
    expect(displayed.runningOrdinal, 2);
    expect(displayed.logSlice, contains('任务乙'));
    expect(displayed.logSlice, isNot(contains('完成甲')));
  });

  test('筛选已完成任务时展示该卡标题与详情', () {
    final displayed = AgentDispatchDisplayedCard.resolve(
      fullLog: log,
      tasks: tasks,
      selectedOrdinal: 1,
      live: live,
      batchRunning: true,
    );

    expect(displayed.progress.currentTitle, '任务甲');
    expect(displayed.progress.currentDetail, '实现筛选');
    expect(displayed.progress.phaseLabel, '已完成');
    expect(displayed.progress.liveCardLabel, '1/2');
    expect(displayed.running, isFalse);
    expect(displayed.canJumpToRunning, isTrue);
    expect(displayed.logSlice, contains('完成甲'));
    expect(displayed.logSlice, isNot(contains('任务乙')));
  });

  test('已在运行中卡片时不显示跳转', () {
    final displayed = AgentDispatchDisplayedCard.resolve(
      fullLog: log,
      tasks: tasks,
      selectedOrdinal: 2,
      live: live,
      batchRunning: true,
    );

    expect(displayed.progress.currentTitle, '任务乙');
    expect(displayed.running, isTrue);
    expect(displayed.canJumpToRunning, isFalse);
  });

  test('批次已结束时仍可查看历史卡片', () {
    final displayed = AgentDispatchDisplayedCard.resolve(
      fullLog: log,
      tasks: tasks,
      selectedOrdinal: 1,
      live: AgentDispatchProgress.idle,
      batchRunning: false,
    );

    expect(displayed.progress.currentTitle, '任务甲');
    expect(displayed.canJumpToRunning, isFalse);
    expect(displayed.runningOrdinal, isNull);
  });
}
