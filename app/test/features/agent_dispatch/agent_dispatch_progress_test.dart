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
