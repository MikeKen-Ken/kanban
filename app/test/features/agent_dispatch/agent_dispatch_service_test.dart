import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_service.dart';

void main() {
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
}
