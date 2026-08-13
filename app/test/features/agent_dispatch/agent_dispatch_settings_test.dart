import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_config.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_credentials.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_prompt.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_service.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_settings.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_worker.dart';

void main() {
  test('新建设置默认使用 Composer 2.5、Force 和 Max', () {
    const settings = AgentDispatchSettings();

    expect(settings.modelId, 'composer-2.5');
    expect(settings.modelParamValues, {'fast': 'true'});
    expect(settings.cardLimitMax, isTrue);
    expect(
      settings.toRunOptions(projectTitleOf: (_) => null).cardLimit,
      isA<AgentDispatchCardLimitMax>(),
    );
  });

  test('缺少新字段的旧设置迁移到新的默认值', () {
    final settings = AgentDispatchSettings.fromJson({});

    expect(settings.modelId, 'composer-2.5');
    expect(settings.modelParamValues, {'fast': 'true'});
    expect(settings.cardLimitMax, isTrue);
  });

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
      modelParamValues: {
        'fast': 'true',
        'reasoning_effort': 'high',
      },
    );
    final opts = settings.toRunOptions(
      projectTitleOf: (id) => id == 'p1' ? '项目甲' : null,
    );
    expect(opts.projectTitle, '项目甲');
    expect(opts.repoPath, r'D:\repo');
    expect(opts.modelParams, [
      (id: 'fast', value: 'true'),
      (id: 'reasoning_effort', value: 'high'),
    ]);
    expect(opts.cardLimit, isA<AgentDispatchCardLimitMax>());
  });

  test('settings JSON 往返保留仓库', () {
    const original = AgentDispatchSettings(
      repoPath: '/tmp/x',
      repoPathByProject: {'a': '/tmp/a'},
      repoPaths: ['/tmp/x', '/tmp/a'],
      modelParamValues: {'fast': 'false', 'effort': 'high'},
    );
    final roundTrip = AgentDispatchSettings.fromJson(original.toJson());
    expect(roundTrip.repoPath, '/tmp/x');
    expect(roundTrip.repoPathByProject['a'], '/tmp/a');
    expect(roundTrip.repoPaths, ['/tmp/x', '/tmp/a']);
    expect(roundTrip.modelParamValues, {'fast': 'false', 'effort': 'high'});
    expect(original.toJson(), isNot(contains('cursorApiKey')));
  });

  test('旧设置会把当前仓库和项目仓库迁移到历史下拉框', () {
    final settings = AgentDispatchSettings.fromJson({
      'repoPath': '/tmp/current',
      'repoPathByProject': {'a': '/tmp/a', 'b': '/tmp/current'},
    });

    expect(settings.repoPaths, ['/tmp/current', '/tmp/a']);
  });

  test('忘记历史仓库时清理对应的项目默认值', () {
    const settings = AgentDispatchSettings(
      repoPath: '/tmp/current',
      repoPaths: ['/tmp/current', '/tmp/remove', '/tmp/keep'],
      repoPathByProject: {
        'current': '/tmp/current',
        'remove': '/tmp/remove',
        'keep': '/tmp/keep',
      },
    );

    final next = settings.forgetRepoPath('/tmp/remove');

    expect(next.repoPath, '/tmp/current');
    expect(next.repoPaths, ['/tmp/current', '/tmp/keep']);
    expect(next.repoPathByProject, {
      'current': '/tmp/current',
      'keep': '/tmp/keep',
    });
  });

  test('旧版单一模型参数迁移到参数映射', () {
    final settings = AgentDispatchSettings.fromJson({
      'effortParamId': 'reasoning_effort',
      'effortParamValue': 'high',
    });

    expect(settings.modelParamValues, {'reasoning_effort': 'high'});
  });

  test('Skill 预览读取全文', () async {
    final temp = await Directory.systemTemp.createTemp('kanban_skill_test_');
    try {
      final skill = File('${temp.path}${Platform.pathSeparator}SKILL.md');
      final content = List.filled(2000, '技').join();
      await skill.writeAsString(content);

      expect(await peekSkillPreview(skill.path), content);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('Worker 显式路径可脱离源码仓库解析', () async {
    final temp = await Directory.systemTemp.createTemp('kanban_worker_test_');
    try {
      final cli = File('${temp.path}${Platform.pathSeparator}cli.js');
      await cli.writeAsString('');
      expect(await resolveAgentDispatchCliPath(cli.path), cli.path);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('自包含 Worker 同时验证运行时与 Cursor SDK', () async {
    final temp = await Directory.systemTemp.createTemp('kanban_worker_bundle_');
    try {
      final dist = Directory('${temp.path}${Platform.pathSeparator}dist');
      final runtime = Directory('${temp.path}${Platform.pathSeparator}runtime');
      final sdk = Directory(
        '${temp.path}${Platform.pathSeparator}node_modules'
        '${Platform.pathSeparator}@cursor${Platform.pathSeparator}sdk',
      );
      final codexBin = Directory(
        '${temp.path}${Platform.pathSeparator}node_modules'
        '${Platform.pathSeparator}@openai${Platform.pathSeparator}codex'
        '${Platform.pathSeparator}bin',
      );
      await dist.create(recursive: true);
      await runtime.create(recursive: true);
      await sdk.create(recursive: true);
      await codexBin.create(recursive: true);
      final cli = File('${dist.path}${Platform.pathSeparator}cli.js');
      final nodeName = Platform.isWindows ? 'node.exe' : 'node';
      await cli.writeAsString('');
      await File('${runtime.path}${Platform.pathSeparator}$nodeName')
          .writeAsString('');
      await File('${codexBin.path}${Platform.pathSeparator}codex.js')
          .writeAsString('');

      final result = await ensureAgentDispatchWorker(
        workerScriptPath: cli.path,
      );
      expect(result.ok, isTrue);
      expect(result.message, contains('Worker 已就绪'));
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('Cursor API Key 只在安全存储中往返', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const credentials = AgentDispatchCredentials();

    await credentials.saveCursorApiKey('  cursor-secret  ');
    expect(await credentials.readStoredCursorApiKey(), 'cursor-secret');
    expect(
      await const AgentDispatchCredentials().readStoredCursorApiKey(),
      'cursor-secret',
    );

    await credentials.deleteCursorApiKey();
    expect(await credentials.readStoredCursorApiKey(), isNull);
  });
}
