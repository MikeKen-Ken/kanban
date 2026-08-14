import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_log.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_log_store.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_progress.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AgentDispatchRegistry.instance.debugReset();
  });

  tearDown(() {
    AgentDispatchRegistry.instance.debugReset();
  });

  test('同一项目复用同一服务，不同项目互相独立', () {
    final registry = AgentDispatchRegistry.instance;
    final a1 = registry.forProject('a');
    final a2 = registry.forProject('a');
    final b = registry.forProject('b');
    expect(identical(a1, a2), isTrue);
    expect(identical(a1, b), isFalse);
  });

  test('运行状态变更会通知监听方', () {
    final service = AgentDispatchRegistry.instance.forProject('p');
    var notified = 0;
    service.addRunningListener(() => notified++);
    service.debugSetProgress(const AgentDispatchProgress(running: true));
    expect(notified, 1);
    service.debugSetProgress(AgentDispatchProgress.idle);
    expect(notified, 2);
  });

  test('无监听方时仍保留日志，重新订阅可看到全文', () async {
    final service = AgentDispatchRegistry.instance.forProject('p1');
    service.appendLog('批次开始');
    service.appendLog('工具输出', level: AgentDispatchLogLevel.success);

    expect(service.logText, contains('批次开始'));
    expect(service.logText, contains('工具输出'));

    var seen = '';
    service.addLogListener((_) => seen = service.logText);
    service.appendLog('窗口关闭后的新行');
    expect(seen, contains('批次开始'));
    expect(seen, contains('窗口关闭后的新行'));

    await service.pendingLogPersist;
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.loadAgentDispatchLog(projectId: 'p1'),
      contains('窗口关闭后的新行'),
    );
    expect(prefs.loadAgentDispatchLog(projectId: 'p2'), isEmpty);
  });

  test('高频 Worker 输出不会让服务日志无限增长', () async {
    final service = AgentDispatchRegistry.instance.forProject('bounded');

    for (var index = 0; index < 5000; index++) {
      service.appendLog('worker line $index');
    }

    final lines = service.logText.split('\n');
    expect(lines, hasLength(3000));
    expect(service.logText, isNot(contains('worker line 1999')));
    expect(service.logText, contains('worker line 2000'));
    expect(service.logText, contains('worker line 4999'));

    await service.pendingLogPersist;
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.loadAgentDispatchLog(projectId: 'bounded').split('\n'),
      hasLength(3000),
    );
  });
}
