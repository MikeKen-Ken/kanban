import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_log.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_log_store.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AgentDispatchService().debugReset();
  });

  tearDown(() {
    AgentDispatchService().debugReset();
  });

  test('AgentDispatchService 为单例', () {
    expect(identical(AgentDispatchService(), AgentDispatchService()), isTrue);
  });

  test('运行状态变更会通知监听方', () {
    final service = AgentDispatchService();
    var notified = 0;
    service.addRunningListener(() => notified++);
    service.removeRunningListener(() {});
    expect(notified, 0);
  });

  test('无监听方时仍保留日志，重新订阅可看到全文', () async {
    final service = AgentDispatchService();
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
    expect(prefs.loadAgentDispatchLog(), contains('窗口关闭后的新行'));
  });
}
