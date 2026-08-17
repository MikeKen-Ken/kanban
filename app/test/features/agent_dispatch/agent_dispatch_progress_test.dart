import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_progress.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_registry.dart';

void main() {
  test('Max 用队列长度作分母，固定张数取较小值', () {
    expect(
      plannedDispatchTotal(
        cardLimitMax: true,
        cardLimitCount: 1,
        queueSize: 8,
      ),
      8,
    );
    expect(
      plannedDispatchTotal(
        cardLimitMax: false,
        cardLimitCount: 10,
        queueSize: 3,
      ),
      3,
    );
    expect(
      plannedDispatchTotal(
        cardLimitMax: false,
        cardLimitCount: 2,
        queueSize: 9,
      ),
      2,
    );
  });

  test('从 Worker 日志解析轮次与已处理张数', () {
    var progress = const AgentDispatchProgress(running: true, totalCards: 5);
    progress = applyWorkerProgressLog(progress, 'Worker 单卡轮次 2/5');
    expect(progress.currentRound, 2);
    progress = applyWorkerProgressLog(
      progress,
      '[success] Worker 确认第 2 次 Skill 只处理一张且已送验；会话已释放',
    );
    expect(progress.processedCards, 2);
    expect(progress.fractionLabel, '2/5');
  });

  test('从日志解析当前卡片内容与实时阶段', () {
    var progress = const AgentDispatchProgress(running: true, totalCards: 12);
    progress = applyWorkerProgressLog(progress, '──────── Worker 单卡轮次 1/12 ────────');
    expect(progress.liveCardLabel, '1/12');
    expect(progress.phaseLabel, '领取');
    progress = applyWorkerProgressLog(progress, '当前卡片：agent 工作台');
    progress = applyWorkerProgressLog(
      progress,
      '当前任务：在日志窗口上方显示 1/12 与实时状态',
    );
    expect(progress.currentTitle, 'agent 工作台');
    expect(progress.currentDetail, contains('实时状态'));
    progress = applyWorkerProgressLog(progress, 'Worker 正在实施当前卡片');
    expect(progress.phaseLabel, '实施');
    progress = applyWorkerProgressLog(progress, '开始 Worker 验证：共 1 条');
    expect(progress.phaseLabel, '测试');
    progress = applyWorkerProgressLog(progress, 'Worker 正在提交并送交验证');
    expect(progress.phaseLabel, '提交');
    progress = applyWorkerProgressLog(progress, '完成后队列：开始「推送」');
    expect(progress.phaseLabel, '推送');
  });

  test('队列中途加卡时 Max 分母随剩余工作量增加', () {
    expect(
      liveDispatchTotal(
        cardLimitMax: true,
        cardLimitCount: 0,
        processedCards: 3,
        remainingQueue: 9,
        hasActiveCard: true,
      ),
      13,
    );
    expect(
      liveDispatchTotal(
        cardLimitMax: true,
        cardLimitCount: 0,
        processedCards: 3,
        remainingQueue: 8,
        hasActiveCard: true,
      ),
      12,
    );
  });

  test('固定张数上限不会因加卡超过上限', () {
    expect(
      liveDispatchTotal(
        cardLimitMax: false,
        cardLimitCount: 10,
        processedCards: 2,
        remainingQueue: 12,
        hasActiveCard: true,
      ),
      10,
    );
  });

  test('总览能读到各项目运行进度', () {
    final registry = AgentDispatchRegistry.instance;
    addTearDown(registry.debugReset);
    registry.debugReset();
    registry.forProject('a').debugSetProgress(
          const AgentDispatchProgress(
            running: true,
            processedCards: 3,
            totalCards: 10,
          ),
        );
    expect(registry.anyRunning, isTrue);
    expect(registry.runningCount, 1);
    expect(registry.progressOf('a').fractionLabel, '3/10');
    expect(registry.progressOf('b').running, isFalse);
  });
}
