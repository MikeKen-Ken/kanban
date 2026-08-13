import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_log_exporter.dart';
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

  test('工具对话记录不会截断失败详情', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final log = '拉取模型失败：\n${'服务端诊断\n' * 20000}';

    await prefs.saveAgentDispatchLog(log);

    expect(prefs.loadAgentDispatchLog(), log);
  });

  test('导出文件名包含本地时间且使用文本扩展名', () {
    expect(
      agentDispatchLogExportFileName(DateTime(2026, 8, 13, 9, 5, 7)),
      'agent-dispatch-20260813-090507.txt',
    );
  });
}
