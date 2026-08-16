import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_credentials.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_prompt.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_service.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_settings.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_worker.dart';

void main() {
  test('新建设置默认使用 Composer 2.5、关闭快速模式、Medium 和 Max', () {
    const settings = AgentDispatchSettings();

    expect(settings.modelId, 'composer-2.5');
    expect(settings.modelParamValues, {
      'fast': 'false',
      'reasoning_effort': 'medium',
    });
    expect(settings.cardLimitMax, isTrue);
    expect(settings.runAfterQueueOnFailure, isTrue);
    expect(settings.allowHighReasoning, isFalse);
    expect(
      settings.toRunOptions(projectTitleOf: (_) => null).cardLimit,
      isA<AgentDispatchCardLimitMax>(),
    );
  });

  test('缺少新字段的旧设置迁移到新的默认值', () {
    final settings = AgentDispatchSettings.fromJson({});

    expect(settings.modelId, 'composer-2.5');
    expect(settings.modelParamValues, {
      'fast': 'false',
      'reasoning_effort': 'medium',
    });
    expect(settings.cardLimitMax, isTrue);
  });

  test('加载设置时记住是否勾选全部以及张数', () {
    final settings = AgentDispatchSettings.fromJson({
      'cardLimitMax': false,
      'cardLimitCount': 7,
    });

    expect(settings.cardLimitMax, isFalse);
    expect(settings.cardLimitCount, 7);
  });

  test('保存设置时保留用户选择的运行次数', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const settings = AgentDispatchSettings(
      cardLimitMax: false,
      cardLimitCount: 7,
    );

    await prefs.saveAgentDispatchSettings(settings);
    final loaded = prefs.loadAgentDispatchSettings();

    expect(loaded.cardLimitMax, isFalse);
    expect(loaded.cardLimitCount, 7);
  });

  test('buildSkillDispatchPrompt 只注入 skill 与 projectId', () {
    final text = buildSkillDispatchPrompt(
      skillMarkdown: '# 看板：做最新一条\n\n## 流程\n',
      projectId: 'proj-1',
    );
    expect(text, contains('Skill 正文'));
    expect(text, contains('projectId:proj-1'));
    expect(text, contains('禁止搜索'));
    expect(text, contains('ready_to_submit'));
    expect(text, contains('禁止调用 pick_next_card'));
    expect(text, contains('禁止在会话内预跑即将交给 ready_to_submit 的 verificationCommands'));
    expect(text, isNot(contains('commit_and_submit_card')));
    expect(text, isNot(contains('name:')));
    expect(text, isNot(contains('dispatchSessionId')));
    expect(text, isNot(contains('CARD_DONE')));
  });

  test('buildSkillDispatchPrompt 剥掉 YAML frontmatter', () {
    final text = buildSkillDispatchPrompt(
      skillMarkdown: '''
---
name: kanban-complete-tasks
description: 由 Agent 调度工作台触发
disable-model-invocation: true
---

# 看板：做最新一条

取卡。
''',
      projectId: 'proj-1',
    );
    expect(text, contains('# 看板：做最新一条'));
    expect(text, contains('取卡。'));
    expect(text, isNot(contains('name: kanban-complete-tasks')));
    expect(text, isNot(contains('disable-model-invocation')));
  });

  test('调用正文始终钉死项目 UUID，不再回退到界面当前项目', () {
    final text = buildSkillDispatchPrompt(
      skillMarkdown: 'skill',
      projectId: 'proj-2',
    );
    expect(text, contains('projectId:proj-2'));
    expect(text, isNot(contains('name:')));
    expect(text, isNot(contains('（空：使用看板当前打开的项目）')));
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
      allowHighReasoning: true,
    );
    final opts = settings.toRunOptions(
      projectTitleOf: (id) => id == 'p1' ? '项目甲' : null,
    );
    expect(opts.projectTitle, '项目甲');
    expect(opts.projectId, 'p1');
    expect(opts.repoPath, r'D:\repo');
    expect(opts.modelParams, [
      (id: 'fast', value: 'true'),
      (id: 'reasoning_effort', value: 'high'),
    ]);
    expect(opts.cardLimit, isA<AgentDispatchCardLimitMax>());
    expect(opts.allowHighReasoning, isTrue);
    expect(opts.engineDefaults['cursor']?.modelId, 'composer-2.5');
    expect(opts.engineDefaults['codex']?.modelId, isNull);
  });

  test('切换平台会记住并恢复各自的模型', () {
    const cursor = AgentDispatchSettings(
      engine: AgentDispatchEngine.cursor,
      modelId: 'composer-2.5',
      modelParamValues: {'fast': 'false', 'reasoning_effort': 'high'},
    );

    final toCodex = cursor.switchEngine(AgentDispatchEngine.codex).copyWith(
      modelId: 'gpt-5',
      modelParamValues: {'model_reasoning_effort': 'low'},
    );
    final back = toCodex.rememberActiveEngineProfile().switchEngine(
          AgentDispatchEngine.cursor,
        );

    expect(back.engine, AgentDispatchEngine.cursor);
    expect(back.modelId, 'composer-2.5');
    expect(back.modelParamValues, {
      'fast': 'false',
      'reasoning_effort': 'high',
    });
    expect(
      back.engineProfiles['codex']?.modelId,
      'gpt-5',
    );
  });

  test('旧设置会把当前引擎模型迁入分平台配置', () {
    final settings = AgentDispatchSettings.fromJson({
      'engine': 'cursor',
      'modelId': 'composer-2.5',
      'modelParamValues': {'fast': 'false', 'reasoning_effort': 'high'},
    });

    expect(settings.engineProfiles['cursor']?.modelId, 'composer-2.5');
    expect(settings.engineProfiles['cursor']?.modelParamValues, {
      'fast': 'false',
      'reasoning_effort': 'high',
    });
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
    expect(roundTrip.allowHighReasoning, isFalse);
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

  test('自包含 Worker 同时验证运行时、依赖与 Cursor 原生模块', () async {
    final temp = await Directory.systemTemp.createTemp('kanban_worker_bundle_');
    try {
      final dist = Directory('${temp.path}${Platform.pathSeparator}dist');
      final runtime = Directory('${temp.path}${Platform.pathSeparator}runtime');
      final sdk = Directory(
        '${temp.path}${Platform.pathSeparator}node_modules'
        '${Platform.pathSeparator}@cursor${Platform.pathSeparator}sdk',
      );
      final sdkNative = Directory(
        '${temp.path}${Platform.pathSeparator}node_modules'
        '${Platform.pathSeparator}@cursor${Platform.pathSeparator}'
        'sdk-win32-x64${Platform.pathSeparator}vendor',
      );
      final mcpClient = Directory(
        '${temp.path}${Platform.pathSeparator}node_modules'
        '${Platform.pathSeparator}@modelcontextprotocol'
        '${Platform.pathSeparator}client',
      );
      final codexBin = Directory(
        '${temp.path}${Platform.pathSeparator}node_modules'
        '${Platform.pathSeparator}@openai${Platform.pathSeparator}codex'
        '${Platform.pathSeparator}bin',
      );
      await dist.create(recursive: true);
      await runtime.create(recursive: true);
      await sdk.create(recursive: true);
      await Directory('${sdkNative.path}${Platform.pathSeparator}tree-sitter')
          .create(recursive: true);
      await Directory(
        '${sdkNative.path}${Platform.pathSeparator}tree-sitter-bash',
      ).create(recursive: true);
      await mcpClient.create(recursive: true);
      await codexBin.create(recursive: true);
      final cli = File('${dist.path}${Platform.pathSeparator}cli.js');
      final nodeName = Platform.isWindows ? 'node.exe' : 'node';
      await cli.writeAsString('');
      await File('${runtime.path}${Platform.pathSeparator}$nodeName')
          .writeAsString('');
      await File('${sdk.path}${Platform.pathSeparator}package.json')
          .writeAsString('{"version":"1.0.28"}');
      await File(
        '${mcpClient.path}${Platform.pathSeparator}package.json',
      ).writeAsString('{}');
      await File(
        '${sdkNative.path}${Platform.pathSeparator}tree-sitter'
        '${Platform.pathSeparator}binding.node',
      ).writeAsString('');
      await File(
        '${sdkNative.path}${Platform.pathSeparator}tree-sitter-bash'
        '${Platform.pathSeparator}binding.node',
      ).writeAsString('');
      await File('${codexBin.path}${Platform.pathSeparator}codex.js')
          .writeAsString('');

      final result = await ensureAgentDispatchWorker(
        workerScriptPath: cli.path,
        commandRunner: (executable, arguments) async {
          if (arguments.contains('--version')) {
            return ProcessResult(1, 0, 'v24.18.0\n', '');
          }
          return ProcessResult(1, 0, '', '');
        },
      );
      expect(result.ok, isTrue);
      expect(result.message, contains('健康检查通过'));
      expect(result.message, contains('Cursor SDK=1.0.28'));
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('Worker 原生模块访问冲突会返回可读诊断', () async {
    final temp = await Directory.systemTemp.createTemp('kanban_worker_crash_');
    try {
      final dist = Directory('${temp.path}${Platform.pathSeparator}dist');
      final runtime = Directory('${temp.path}${Platform.pathSeparator}runtime');
      final modules =
          Directory('${temp.path}${Platform.pathSeparator}node_modules');
      await dist.create(recursive: true);
      await runtime.create(recursive: true);
      await Directory('${modules.path}${Platform.pathSeparator}@cursor'
              '${Platform.pathSeparator}sdk')
          .create(recursive: true);
      await Directory('${modules.path}${Platform.pathSeparator}@cursor'
              '${Platform.pathSeparator}sdk-win32-x64'
              '${Platform.pathSeparator}vendor${Platform.pathSeparator}tree-sitter')
          .create(recursive: true);
      await Directory('${modules.path}${Platform.pathSeparator}@cursor'
              '${Platform.pathSeparator}sdk-win32-x64'
              '${Platform.pathSeparator}vendor${Platform.pathSeparator}tree-sitter-bash')
          .create(recursive: true);
      await Directory(
              '${modules.path}${Platform.pathSeparator}@modelcontextprotocol'
              '${Platform.pathSeparator}client')
          .create(recursive: true);
      await Directory('${modules.path}${Platform.pathSeparator}@openai'
              '${Platform.pathSeparator}codex${Platform.pathSeparator}bin')
          .create(recursive: true);
      final cli = File('${dist.path}${Platform.pathSeparator}cli.js');
      await cli.writeAsString('');
      await File('${runtime.path}${Platform.pathSeparator}node.exe')
          .writeAsString('');
      await File('${modules.path}${Platform.pathSeparator}@cursor'
              '${Platform.pathSeparator}sdk${Platform.pathSeparator}package.json')
          .writeAsString('{"version":"1.0.28"}');
      await File('${modules.path}${Platform.pathSeparator}@modelcontextprotocol'
              '${Platform.pathSeparator}client${Platform.pathSeparator}package.json')
          .writeAsString('{}');
      await File('${modules.path}${Platform.pathSeparator}@openai'
              '${Platform.pathSeparator}codex${Platform.pathSeparator}bin'
              '${Platform.pathSeparator}codex.js')
          .writeAsString('');
      for (final grammar in ['tree-sitter', 'tree-sitter-bash']) {
        await File('${modules.path}${Platform.pathSeparator}@cursor'
                '${Platform.pathSeparator}sdk-win32-x64'
                '${Platform.pathSeparator}vendor${Platform.pathSeparator}$grammar'
                '${Platform.pathSeparator}binding.node')
            .writeAsString('');
      }

      final health = await inspectAgentDispatchWorker(
        cli.path,
        commandRunner: (executable, arguments) async {
          if (arguments.contains('--version')) {
            return ProcessResult(1, 0, 'v24.18.0\n', '');
          }
          return ProcessResult(1, -1073741819, '', '');
        },
      );

      expect(health.ok, isFalse);
      expect(health.error, contains('原生模块健康检查失败'));
      expect(health.error, contains('-1073741819'));
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

  test('Cursor API Key 支持多个 Key 切换与删除', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const credentials = AgentDispatchCredentials();

    await credentials.saveCursorApiKey('first-key', label: '主账号');
    await credentials.saveCursorApiKey('second-key', label: '备用');
    final keys = await credentials.listStoredCursorApiKeys();
    expect(keys, hasLength(2));
    expect(keys.where((item) => item.isActive).single.label, '备用');
    expect(await credentials.readStoredCursorApiKey(), 'second-key');

    final firstId = keys.firstWhere((item) => item.label == '主账号').id;
    await credentials.setActiveCursorApiKey(firstId);
    expect(await credentials.readStoredCursorApiKey(), 'first-key');

    await credentials.deleteCursorApiKey(firstId);
    final remaining = await credentials.listStoredCursorApiKeys();
    expect(remaining, hasLength(1));
    expect(remaining.single.label, '备用');
    expect(await credentials.readStoredCursorApiKey(), 'second-key');
  });

  test('再次保存已有 Key 只切换当前项，不覆盖其它账号', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const credentials = AgentDispatchCredentials();

    await credentials.saveCursorApiKey('first-key', label: '主账号');
    await credentials.saveCursorApiKey('second-key', label: '备用');
    await credentials.saveCursorApiKey('first-key', label: '主账号');
    final keys = await credentials.listStoredCursorApiKeys();

    expect(keys, hasLength(2));
    expect(keys.where((item) => item.isActive).single.label, '主账号');
    expect(await credentials.readStoredCursorApiKey(), 'first-key');
  });

  test('Cursor API Key 可原地替换当前 Key', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const credentials = AgentDispatchCredentials();

    await credentials.saveCursorApiKey('first-key', label: '主账号');
    await credentials.replaceActiveCursorApiKey('updated-key');
    final keys = await credentials.listStoredCursorApiKeys();

    expect(keys, hasLength(1));
    expect(keys.single.label, '主账号');
    expect(await credentials.readStoredCursorApiKey(), 'updated-key');
  });

  test('访问冲突退出码给出明确说明', () {
    final message = describeWorkerExitWithoutOutput(-1073741819);
    expect(message, contains('0xC0000005'));
    expect(message, contains('send'));
    expect(message, isNot(contains('SQLite')));
    expect(describeWorkerExitWithoutOutput(1), contains('退出码 1'));
  });
}
