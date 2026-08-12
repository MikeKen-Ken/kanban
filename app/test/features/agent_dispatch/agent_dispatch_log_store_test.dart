import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_log_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('工具对话记录可持久化并清空', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await prefs.saveAgentDispatchLog('第一轮\n工具输出');
    expect(prefs.loadAgentDispatchLog(), '第一轮\n工具输出');

    await prefs.clearAgentDispatchLog();
    expect(prefs.loadAgentDispatchLog(), isEmpty);
  });
}
