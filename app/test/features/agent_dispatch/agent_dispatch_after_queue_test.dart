import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_after_queue.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_after_queue_field.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

AgentDispatchAfterQueueHost _host({
  Future<void> Function()? uploadAll,
  Future<void> Function()? gitPush,
  Future<void> Function()? sleep,
  Future<void> Function()? shutdown,
}) {
  return AgentDispatchAfterQueueHost(
    uploadAll: uploadAll ?? () async => fail('不应上传'),
    gitPush: gitPush ?? () async => fail('不应推送'),
    sleep: sleep ?? () async => fail('不应休眠'),
    shutdown: shutdown ?? () async => fail('不应关机'),
  );
}

void main() {
  test('按钮文案使用短标签', () {
    expect(AgentDispatchAfterStep.webdavUpload.label, '上传');
    expect(AgentDispatchAfterStep.gitPush.label, '推送');
    expect(AgentDispatchAfterStep.sleep.label, '休眠');
    expect(AgentDispatchAfterStep.shutdown.label, '关机');
  });

  test('解析完成后队列时去重并保持顺序', () {
    expect(
      parseAgentDispatchAfterQueue(
        ['webdavUpload', 'gitPush', 'sleep', 'webdavUpload'],
      ),
      [
        AgentDispatchAfterStep.webdavUpload,
        AgentDispatchAfterStep.gitPush,
        AgentDispatchAfterStep.sleep,
      ],
    );
  });

  test('上传完成前不会进入休眠', () async {
    var uploadDone = false;
    var slept = false;
    await runAgentDispatchAfterQueue(
      steps: const [
        AgentDispatchAfterStep.webdavUpload,
        AgentDispatchAfterStep.sleep,
      ],
      host: _host(
        uploadAll: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          uploadDone = true;
        },
        sleep: () async {
          expect(uploadDone, isTrue);
          slept = true;
        },
      ),
    );
    expect(slept, isTrue);
  });

  test('推送完成前不会进入休眠', () async {
    var pushed = false;
    var slept = false;
    await runAgentDispatchAfterQueue(
      steps: const [
        AgentDispatchAfterStep.gitPush,
        AgentDispatchAfterStep.sleep,
      ],
      host: _host(
        gitPush: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          pushed = true;
        },
        sleep: () async {
          expect(pushed, isTrue);
          slept = true;
        },
      ),
    );
    expect(slept, isTrue);
  });

  test('上传失败时不执行后续休眠', () async {
    var slept = false;
    await expectLater(
      runAgentDispatchAfterQueue(
        steps: const [
          AgentDispatchAfterStep.webdavUpload,
          AgentDispatchAfterStep.sleep,
        ],
        host: _host(
          uploadAll: () async => throw Exception('上传失败'),
          sleep: () async => slept = true,
        ),
      ),
      throwsException,
    );
    expect(slept, isFalse);
  });

  test('推送失败时不执行后续休眠', () async {
    var slept = false;
    await expectLater(
      runAgentDispatchAfterQueue(
        steps: const [
          AgentDispatchAfterStep.gitPush,
          AgentDispatchAfterStep.sleep,
        ],
        host: _host(
          gitPush: () async => throw Exception('推送失败'),
          sleep: () async => slept = true,
        ),
      ),
      throwsException,
    );
    expect(slept, isFalse);
  });

  test('保存并加载完成后队列', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const settings = AgentDispatchSettings(
      afterQueue: [
        AgentDispatchAfterStep.webdavUpload,
        AgentDispatchAfterStep.gitPush,
        AgentDispatchAfterStep.sleep,
      ],
    );

    await prefs.saveAgentDispatchSettings(settings);
    final loaded = prefs.loadAgentDispatchSettings();

    expect(loaded.afterQueue, settings.afterQueue);
  });

  test('缺少 afterQueue 的旧设置回退为空队列', () {
    final settings = AgentDispatchSettings.fromJson({});
    expect(settings.afterQueue, isEmpty);
  });

  testWidgets('添加按钮只显示短文案', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentDispatchAfterQueueField(
            steps: const [],
            enabled: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('上传'), findsOneWidget);
    expect(find.text('推送'), findsOneWidget);
    expect(find.text('休眠'), findsOneWidget);
    expect(find.text('关机'), findsOneWidget);
    expect(find.text('添加上传'), findsNothing);
    expect(find.text('WebDAV 全量上传'), findsNothing);
  });

  test('工作区不干净时中止且不 fetch/rebase/push', () async {
    final commands = <List<String>>[];
    await expectLater(
      gitPushWithRebase(
        repoPath: r'D:\repo',
        runner: (executable, arguments, {workingDirectory, environment}) async {
          expect(executable, 'git');
          commands.add(arguments);
          if (arguments.contains('--is-inside-work-tree')) {
            return ProcessResult(1, 0, 'true\n', '');
          }
          if (arguments.contains('--porcelain')) {
            return ProcessResult(1, 0, ' M README.md\n', '');
          }
          return ProcessResult(1, 0, '', '');
        },
      ),
      throwsA(
        isA<Exception>().having(
          (error) => '$error',
          'message',
          contains('工作区不干净'),
        ),
      ),
    );
    expect(
      commands.any((args) => args.contains('fetch') || args.contains('push')),
      isFalse,
    );
  });

  test('rebase 冲突时 abort 且不 push、不 force', () async {
    final commands = <List<String>>[];
    await expectLater(
      gitPushWithRebase(
        repoPath: r'D:\repo',
        runner: (executable, arguments, {workingDirectory, environment}) async {
          commands.add(arguments);
          expect(_gitArgHasForceForTest(arguments), isFalse);
          if (arguments.first == 'rebase') {
            if (arguments.contains('--abort')) {
              return ProcessResult(1, 0, '', '');
            }
            return ProcessResult(1, 1, '', 'CONFLICT\n');
          }
          return _scriptedGit(arguments, aheadBehind: '1\t2\n');
        },
      ),
      throwsA(
        isA<Exception>().having(
          (error) => '$error',
          'message',
          contains('已 abort'),
        ),
      ),
    );
    expect(commands.any((args) => args.contains('--abort')), isTrue);
    expect(commands.any((args) => args.first == 'push'), isFalse);
  });

  test('仅本地超前后普通 push', () async {
    final commands = <List<String>>[];
    await gitPushWithRebase(
      repoPath: r'D:\repo',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        commands.add(arguments);
        expect(_gitArgHasForceForTest(arguments), isFalse);
        expect(environment?['GIT_TERMINAL_PROMPT'], '0');
        if (arguments.first == 'push') {
          return ProcessResult(1, 0, '', '');
        }
        return _scriptedGit(arguments, aheadBehind: '2\t0\n');
      },
    );
    expect(commands.any((args) => args.first == 'fetch'), isTrue);
    expect(commands.any((args) => args.first == 'rebase'), isFalse);
    expect(
      commands.where((args) => args.first == 'push').single,
      ['push'],
    );
  });

  test('落后且无本地提交时快进而不是 rebase', () async {
    final commands = <List<String>>[];
    var countCalls = 0;
    await gitPushWithRebase(
      repoPath: r'D:\repo',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        commands.add(arguments);
        expect(_gitArgHasForceForTest(arguments), isFalse);
        if (arguments.contains('--count')) {
          countCalls += 1;
          return ProcessResult(1, 0, countCalls == 1 ? '0\t3\n' : '0\t0\n', '');
        }
        if (arguments.first == 'merge') {
          expect(arguments, ['merge', '--ff-only', '@{u}']);
          return ProcessResult(1, 0, '', '');
        }
        return _scriptedGit(arguments);
      },
    );
    expect(commands.any((args) => args.first == 'rebase'), isFalse);
    expect(commands.any((args) => args.first == 'push'), isFalse);
    expect(commands.any((args) => args.first == 'merge'), isTrue);
  });

  test('分叉时 rebase 成功后再普通 push', () async {
    final commands = <List<String>>[];
    var countCalls = 0;
    await gitPushWithRebase(
      repoPath: r'D:\repo',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        commands.add(arguments);
        expect(_gitArgHasForceForTest(arguments), isFalse);
        if (arguments.first == 'rebase') {
          expect(arguments, ['rebase', '@{u}']);
          return ProcessResult(1, 0, '', '');
        }
        if (arguments.first == 'push') {
          return ProcessResult(1, 0, '', '');
        }
        if (arguments.contains('--count')) {
          countCalls += 1;
          return ProcessResult(
            1,
            0,
            countCalls == 1 ? '1\t2\n' : '1\t0\n',
            '',
          );
        }
        return _scriptedGit(arguments);
      },
    );
    expect(commands.any((args) => args.contains('--abort')), isFalse);
    expect(
      commands.where((args) => args.first == 'push').single,
      ['push'],
    );
  });
}

ProcessResult _scriptedGit(
  List<String> arguments, {
  String aheadBehind = '0\t0\n',
}) {
  if (arguments.contains('--is-inside-work-tree')) {
    return ProcessResult(1, 0, 'true\n', '');
  }
  if (arguments.contains('--porcelain')) {
    return ProcessResult(1, 0, '', '');
  }
  if (arguments.contains('--verify')) {
    return ProcessResult(1, 1, '', '');
  }
  if (arguments.contains('--abbrev-ref') && arguments.contains('HEAD')) {
    return ProcessResult(1, 0, 'main\n', '');
  }
  if (arguments.contains('--count')) {
    return ProcessResult(1, 0, aheadBehind, '');
  }
  if (arguments.contains('@{u}') && arguments.contains('--abbrev-ref')) {
    return ProcessResult(1, 0, 'origin/main\n', '');
  }
  if (arguments.contains('--get')) {
    return ProcessResult(1, 0, 'origin\n', '');
  }
  if (arguments.first == 'fetch') {
    return ProcessResult(1, 0, '', '');
  }
  fail('意外命令：$arguments');
}

bool _gitArgHasForceForTest(List<String> arguments) {
  return arguments.any(
    (arg) =>
        arg == '--force' ||
        arg == '-f' ||
        arg == '--force-with-lease' ||
        arg.startsWith('--force-with-lease='),
  );
}
