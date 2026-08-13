import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_log.dart';

void main() {
  test('日志文本保留级别，供界面着色和导出诊断', () {
    final line = const AgentDispatchLogEntry(
      '调用失败',
      level: AgentDispatchLogLevel.error,
    ).format(DateTime(2026, 8, 13, 9, 8, 7));

    expect(line, '[09:08:07] [失败] 调用失败');
    expect(AgentDispatchLogEntry.levelOf(line), AgentDispatchLogLevel.error);
  });
}
