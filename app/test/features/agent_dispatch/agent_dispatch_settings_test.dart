import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_config.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_prompt.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_settings.dart';

void main() {
  test('buildSkillDispatchPrompt 注入 skill 与 name', () {
    final text = buildSkillDispatchPrompt(
      skillMarkdown: '# 看板：做最新一条\n\n## 流程\n',
      projectTitle: '我的项目',
      cardLimit: AgentDispatchCardLimit.count(3),
    );
    expect(text, contains('Skill 正文'));
    expect(text, contains('name:我的项目'));
    expect(text, contains('最多 3 张'));
  });

  test('不指定项目时调用正文为空说明', () {
    final text = buildSkillDispatchPrompt(
      skillMarkdown: 'skill',
      projectTitle: null,
      cardLimit: AgentDispatchCardLimit.max,
    );
    expect(text, contains('（空：使用看板当前打开的项目）'));
    expect(text, contains('不限'));
    expect(text, isNot(contains('name:')));
  });

  test('toRunOptions：仓库必填字段与 Max', () {
    const settings = AgentDispatchSettings(
      engine: AgentDispatchEngine.cursor,
      useProject: true,
      projectId: 'p1',
      repoPath: r'D:\repo',
      modelId: 'composer-2.5',
      cardLimitMax: true,
      effortParamId: 'reasoning_effort',
      effortParamValue: 'high',
    );
    final opts = settings.toRunOptions(
      projectTitleOf: (id) => id == 'p1' ? '项目甲' : null,
    );
    expect(opts.projectTitle, '项目甲');
    expect(opts.repoPath, r'D:\repo');
    expect(opts.modelParams.single.id, 'reasoning_effort');
    expect(opts.cardLimit, isA<AgentDispatchCardLimitMax>());
  });

  test('settings JSON 往返保留仓库', () {
    const original = AgentDispatchSettings(
      repoPath: '/tmp/x',
      repoPathByProject: {'a': '/tmp/a'},
    );
    final roundTrip = AgentDispatchSettings.fromJson(original.toJson());
    expect(roundTrip.repoPath, '/tmp/x');
    expect(roundTrip.repoPathByProject['a'], '/tmp/a');
  });
}
