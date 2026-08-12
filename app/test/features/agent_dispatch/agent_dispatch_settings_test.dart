import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_config.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_credentials.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_prompt.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_settings.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_worker.dart';

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
    expect(original.toJson(), isNot(contains('cursorApiKey')));
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

    await credentials.deleteCursorApiKey();
    expect(await credentials.readStoredCursorApiKey(), isNull);
  });
}
