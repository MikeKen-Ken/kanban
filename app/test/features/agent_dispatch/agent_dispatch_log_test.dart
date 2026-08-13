import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_log.dart';

void main() {
  test('日志文本保留来源与级别，供界面着色和导出诊断', () {
    final line = const AgentDispatchLogEntry(
      '调用失败',
      level: AgentDispatchLogLevel.error,
      source: AgentDispatchLogSource.mcp,
    ).format(DateTime(2026, 8, 13, 9, 8, 7));

    expect(line, '[09:08:07] [MCP] [失败] 调用失败');
    expect(AgentDispatchLogEntry.levelOf(line), AgentDispatchLogLevel.error);
    expect(AgentDispatchLogEntry.sourceOf(line), AgentDispatchLogSource.mcp);
  });

  test('兼容旧格式日志行', () {
    final line = '[09:08:07] [失败] 调用失败';
    expect(AgentDispatchLogEntry.levelOf(line), AgentDispatchLogLevel.error);
    expect(AgentDispatchLogEntry.sourceOf(line), AgentDispatchLogSource.system);
  });

  test('解析 Worker stdout 的来源与级别前缀', () {
    final entry = AgentDispatchLogEntry.parseWorkerLine(
      '[success] [ai] 助手：已完成',
    );
    expect(entry.level, AgentDispatchLogLevel.success);
    expect(entry.source, AgentDispatchLogSource.ai);
    expect(entry.message, '助手：已完成');
  });

  test('会话指标行拆出重点着色片段', () {
    final line =
        '[09:08:07] [Worker] [信息] 本会话 token：input=12 output=34 total=46';
    final segments = AgentDispatchLogHighlight.segments(line);

    expect(
      segments.where((segment) => segment.emphasis).map((segment) => segment.text),
      ['本会话 token', 'input=12', 'output=34', 'total=46'],
    );
  });

  test('普通日志行不拆分重点片段', () {
    final segments = AgentDispatchLogHighlight.segments('助手：正在处理任务');
    expect(segments, [(text: '助手：正在处理任务', emphasis: false)]);
  });
}
