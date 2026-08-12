import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_config.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_prompt.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_settings.dart';

void main() {
  test('buildAgentDispatchPrompt 含卡片与仓库信息', () {
    final text = buildAgentDispatchPrompt(
      projectId: 'p1',
      cardId: 'c1',
      cardTitle: '修登录',
      cardDescription: '备注内容',
      workScope: {
        'workMode': 'normal',
        'workItems': [
          {'type': 'checklist', 'text': '改 auth'},
        ],
      },
      repoPath: r'C:\work\demo',
    );
    expect(text, contains('修登录'));
    expect(text, contains('c1'));
    expect(text, contains(r'C:\work\demo'));
    expect(text, contains('改 auth'));
  });

  test('toRunOptions 尊重复选框', () {
    const settings = AgentDispatchSettings(
      engine: AgentDispatchEngine.codex,
      projectId: 'proj',
      repoPath: r'D:\repo',
      model: 'composer-2.5',
      effort: AgentDispatchEffort.high,
      maxCards: 5,
      useProject: true,
      useRepo: true,
      useModel: false,
      useEffort: true,
      useMultiCard: true,
    );
    final opts = settings.toRunOptions(activeProjectId: 'other');
    expect(opts.engine, AgentDispatchEngine.codex);
    expect(opts.projectId, 'proj');
    expect(opts.repoPath, r'D:\repo');
    expect(opts.model, isNull);
    expect(opts.effort, AgentDispatchEffort.high);
    expect(opts.maxCards, 5);
  });

  test('settings JSON 往返', () {
    const original = AgentDispatchSettings(
      engine: AgentDispatchEngine.cursor,
      useRepo: true,
      repoPath: '/tmp/x',
      repoPathByProject: {'a': '/tmp/a'},
    );
    final roundTrip = AgentDispatchSettings.fromJson(original.toJson());
    expect(roundTrip.engine, AgentDispatchEngine.cursor);
    expect(roundTrip.repoPath, '/tmp/x');
    expect(roundTrip.repoPathByProject['a'], '/tmp/a');
  });
}
