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
    final success = AgentDispatchLogEntry.parseWorkerLine(
      '[success] [ai] 助手：已完成',
    );
    expect(success.level, AgentDispatchLogLevel.success);
    expect(success.source, AgentDispatchLogSource.ai);
    expect(success.message, '助手：已完成');

    final warning = AgentDispatchLogEntry.parseWorkerLine(
      '[warning] [shell] warning: LF will be replaced by CRLF',
    );
    expect(warning.level, AgentDispatchLogLevel.warning);
    expect(warning.source, AgentDispatchLogSource.shell);
    expect(warning.message, 'warning: LF will be replaced by CRLF');

    final error = AgentDispatchLogEntry.parseWorkerLine(
      '[error] [mcp] 工具失败：ready_to_submit 看板未就绪',
    );
    expect(error.level, AgentDispatchLogLevel.error);
    expect(error.source, AgentDispatchLogSource.mcp);
    expect(error.message, '工具失败：ready_to_submit 看板未就绪');
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

  test('会话 token 行高亮缓存字段', () {
    final line =
        '[09:08:07] [Worker] [信息] 本会话 token：input=1 output=2 cacheRead=3 cacheWrite=0 total=6';
    final segments = AgentDispatchLogHighlight.segments(line);
    expect(
      segments.where((segment) => segment.emphasis).map((segment) => segment.text),
      [
        '本会话 token',
        'input=1',
        'output=2',
        'cacheRead=3',
        'cacheWrite=0',
        'total=6',
      ],
    );
  });

  test('没有具体内容的进度行视为低价值', () {
    expect(
      AgentDispatchLogEntry.isLowValue('[09:08:07] [AI] [信息] 思考中…'),
      isTrue,
    );
    expect(
      AgentDispatchLogEntry.isLowValue('[09:08:07] [MCP] [信息] 工具：glob'),
      isTrue,
    );
    expect(
      AgentDispatchLogEntry.isLowValue(
        '[09:08:07] [MCP] [信息] 工具：grep {"pattern":"foo"}',
      ),
      isFalse,
    );
    expect(
      AgentDispatchLogEntry.isLowValue('[09:08:07] [命令] [信息] 命令：git status'),
      isFalse,
    );
  });

  test('普通日志行不拆分重点片段', () {
    final segments = AgentDispatchLogHighlight.segments('助手：正在处理任务');
    expect(segments, [(text: '助手：正在处理任务', emphasis: false)]);
  });
}
