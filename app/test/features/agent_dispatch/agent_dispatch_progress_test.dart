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

  test('进行中第二张时总览用轮次而不是已完成数', () {
    var progress = const AgentDispatchProgress(
      running: true,
      processedCards: 0,
      totalCards: 2,
    );
    progress = applyWorkerProgressLog(progress, 'Worker 单卡轮次 2/2');
    expect(progress.fractionLabel, '0/2');
    expect(progress.liveCardLabel, '2/2');
    expect(progress.fraction, 0.5);
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

  test('提交与送验完成日志累加已处理张数，且批次完成行同步阶段', () {
    var progress = const AgentDispatchProgress(
      running: true,
      totalCards: 4,
      cardLimitMax: true,
    );
    progress =
        applyWorkerProgressLog(progress, '──────── Worker 单卡轮次 1/4 ────────');
    progress = applyWorkerProgressLog(
      progress,
      '卡片 abc 已验证、提交并送交人工验证',
    );
    expect(progress.processedCards, 1);
    expect(progress.phaseLabel, 'Submit');

    progress =
        applyWorkerProgressLog(progress, '──────── Worker 单卡轮次 2/4 ────────');
    progress = applyWorkerProgressLog(progress, '咨询卡 def 已送交验证');
    expect(progress.processedCards, 2);
    expect(progress.phaseLabel, 'Verify');

    progress = applyWorkerProgressLog(progress, '已恢复 pending 会话 session-1');
    expect(progress.processedCards, 3);

    progress = applyWorkerProgressLog(
      progress,
      '验证已由 Agent 会话完成，Worker 不再复跑测试',
    );
    expect(progress.processedCards, 3);
    expect(progress.phaseLabel, 'Submit');

    progress = applyWorkerProgressLog(
      progress,
      'Worker 批次完成：当前无更多卡片；已处理 3 张',
    );
    expect(progress.processedCards, 3);
    expect(progress.phaseLabel, 'Complete');
  });

  test('English batch completion logs update the processed count', () {
    var progress = const AgentDispatchProgress(running: true, totalCards: 4);
    progress = applyWorkerProgressLog(
      progress,
      'Worker batch completed: Batch limit reached; processed 3 card(s)',
    );

    expect(progress.processedCards, 3);
    expect(progress.phaseLabel, 'Complete');
  });

  test('已处理张数参与实时分母，完成后不会把 4/10 收成 4/7', () {
    const progress = AgentDispatchProgress(
      running: true,
      processedCards: 3,
      totalCards: 10,
      currentRound: 4,
      cardLimitMax: true,
    );
    final live = applyLiveBoardQueue(
      progress,
      remainingQueue: 6,
      hasActiveCard: true,
    );
    expect(live.liveCardLabel, '4/10');
    expect(live.totalCards, 10);
  });

  test('从日志解析当前卡片内容与实时阶段', () {
    var progress = const AgentDispatchProgress(running: true, totalCards: 12);
    progress =
        applyWorkerProgressLog(progress, '──────── Worker 单卡轮次 1/12 ────────');
    expect(progress.liveCardLabel, '1/12');
    expect(progress.phaseLabel, 'Claim');
    progress = applyWorkerProgressLog(progress, '当前卡片：agent 工作台');
    progress = applyWorkerProgressLog(
      progress,
      '当前任务：在日志窗口上方显示 1/12 与实时状态',
    );
    expect(progress.currentTitle, 'agent 工作台');
    expect(progress.currentDetail, contains('实时状态'));
    progress = applyWorkerProgressLog(progress, 'Worker 正在实施当前卡片');
    expect(progress.phaseLabel, 'Implement');
    progress = applyWorkerProgressLog(
      progress,
      'Agent 会话暂时失败（第 2/5 次）：connection lost；2000ms 后自动重试',
    );
    expect(progress.phaseLabel, 'Retry');
    progress =
        applyWorkerProgressLog(progress, '验证已由 Agent 会话完成，Worker 不再复跑测试');
    expect(progress.phaseLabel, 'Submit');
    progress = applyWorkerProgressLog(progress, 'Worker 正在提交并送交验证');
    expect(progress.phaseLabel, 'Submit');
    progress = applyWorkerProgressLog(progress, '完成后队列：开始「推送」');
    expect(progress.phaseLabel, 'Push');
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

  test('当前卡已离开进行中但尚未计入已处理时，两张待办仍显示 1/2', () {
    expect(
      liveDispatchTotal(
        cardLimitMax: true,
        cardLimitCount: 0,
        processedCards: 0,
        remainingQueue: 1,
        hasActiveCard: false,
        currentRound: 1,
      ),
      2,
    );
    const progress = AgentDispatchProgress(
      running: true,
      processedCards: 0,
      totalCards: 2,
      currentRound: 1,
      cardLimitMax: true,
    );
    final live = applyLiveBoardQueue(
      progress,
      remainingQueue: 1,
      hasActiveCard: false,
    );
    expect(live.liveCardLabel, '1/2');
    expect(live.totalCards, 2);
  });

  test('当前会话后停止不再把队列剩余计入分母', () {
    expect(
      liveDispatchTotal(
        cardLimitMax: true,
        cardLimitCount: 0,
        processedCards: 2,
        remainingQueue: 8,
        hasActiveCard: true,
        drainAfterCurrent: true,
      ),
      3,
    );
    expect(
      clampedTotalAfterStop(
        const AgentDispatchProgress(
          running: true,
          processedCards: 2,
          totalCards: 10,
          currentRound: 3,
        ),
      ),
      3,
    );
  });

  test('停止后续卡片后 Worker 轮次日志不再把分母抬回去', () {
    var progress = const AgentDispatchProgress(
      running: true,
      processedCards: 2,
      totalCards: 3,
      currentRound: 3,
      drainAfterCurrent: true,
    );
    progress = applyWorkerProgressLog(progress, 'Worker 单卡轮次 3/10');
    expect(progress.liveCardLabel, '3/3');
    expect(progress.totalCards, 3);
  });

  test('Max 模式忽略 Worker 日志里的 999 上限分母', () {
    var progress = const AgentDispatchProgress(
      running: true,
      processedCards: 0,
      totalCards: 4,
      cardLimitMax: true,
    );
    progress =
        applyWorkerProgressLog(progress, '──────── Worker 单卡轮次 1/999 ────────');
    expect(progress.currentRound, 1);
    expect(progress.liveCardLabel, '1/4');
    expect(progress.totalCards, 4);
  });

  test('无分母的 Max 轮次日志仍更新当前张数', () {
    var progress = const AgentDispatchProgress(
      running: true,
      processedCards: 0,
      totalCards: 4,
      cardLimitMax: true,
    );
    progress =
        applyWorkerProgressLog(progress, '──────── Worker 单卡轮次 1 ────────');
    expect(progress.liveCardLabel, '1/4');
  });

  test('Max 用看板实时队列覆盖被 999 抬高的分母', () {
    const inflated = AgentDispatchProgress(
      running: true,
      processedCards: 0,
      totalCards: 999,
      currentRound: 1,
      cardLimitMax: true,
    );
    final live = applyLiveBoardQueue(
      inflated,
      remainingQueue: 3,
      hasActiveCard: true,
    );
    expect(live.liveCardLabel, '1/4');
  });

  test('固定张数校正时分母不低于当前轮次，避免 4/2', () {
    const progress = AgentDispatchProgress(
      running: true,
      processedCards: 3,
      totalCards: 4,
      currentRound: 4,
      cardLimitMax: false,
      cardLimitCount: 2,
    );
    final live = applyLiveBoardQueue(
      progress,
      remainingQueue: 0,
      hasActiveCard: true,
    );
    expect(live.liveCardLabel, '4/4');
    expect(live.totalCards, 4);
    expect(live.fraction, 0.75);
  });

  test('轮次超前时分母在展示层同步抬升', () {
    const progress = AgentDispatchProgress(
      running: true,
      processedCards: 1,
      totalCards: 2,
      currentRound: 4,
    );
    expect(progress.liveCardLabel, '4/4');
    expect(progress.fraction, 0.75);
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

  test('轮次日志记下本卡开始时间，覆盖日志更新引擎与模型', () {
    final started = DateTime(2026, 8, 18, 18, 0, 0);
    var progress = AgentDispatchProgress(
      running: true,
      totalCards: 3,
      engine: 'codex',
      model: 'gpt-5',
      batchStartedAt: started,
    );
    progress = applyWorkerProgressLog(
      progress,
      'Worker 单卡轮次 1/3',
      now: started.add(const Duration(minutes: 2)),
    );
    expect(progress.cardStartedAt, started.add(const Duration(minutes: 2)));
    progress = applyWorkerProgressLog(
      progress,
      '本卡覆盖：engine=cursor model=composer-2.5 params=[] cardId=abc',
    );
    expect(progress.engine, 'cursor');
    expect(progress.model, 'composer-2.5');
    progress = applyWorkerProgressLog(
      progress,
      '本卡覆盖：engine=cursor model=composer-2.5 params=[{"id":"fast","value":"true"},{"id":"context","value":"272k"}] cardId=abc',
    );
    expect(progress.modelParams, {
      'fast': 'true',
      'context': '272k',
    });
    expect(
      progress.batchElapsedSeconds(
          now: started.add(const Duration(minutes: 5))),
      5 * 60,
    );
    expect(
      progress.cardElapsedSeconds(now: started.add(const Duration(minutes: 5))),
      3 * 60,
    );
  });

  test('English Worker logs update round, title, and completion phase', () {
    var progress = const AgentDispatchProgress(
      running: true,
      totalCards: 2,
      cardLimitMax: true,
    );
    progress = applyWorkerProgressLog(
      progress,
      '──────── Worker card round 1/2 ────────',
    );
    expect(progress.currentRound, 1);
    progress =
        applyWorkerProgressLog(progress, 'Current card: Translate scripts');
    expect(progress.currentTitle, 'Translate scripts');
    progress = applyWorkerProgressLog(
      progress,
      'Worker is processing the current card',
    );
    expect(progress.phaseLabel, 'Implement');
    progress = applyWorkerProgressLog(
      progress,
      'Card abc was validated, committed, and submitted for manual verification',
    );
    expect(progress.processedCards, 1);
    expect(progress.phaseLabel, 'Submit');
    progress = applyWorkerProgressLog(
      progress,
      'Card override: engine=cursor model=composer-2.5 params=[] cardId=abc',
    );
    expect(progress.engine, 'cursor');
    expect(progress.model, 'composer-2.5');
  });
}
