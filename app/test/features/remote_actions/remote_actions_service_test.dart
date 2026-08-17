import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_settings.dart';
import 'package:kanban/features/remote_actions/remote_actions_service.dart';

void main() {
  test('优先使用当前项目绑定的仓库路径', () {
    const settings = AgentDispatchSettings(
      repoPath: 'C:\\fallback',
      repoPathByProject: {'p1': 'C:\\project-repo'},
    );

    expect(
      repoPathForRemoteActions(settings: settings, projectId: 'p1'),
      'C:\\project-repo',
    );
    expect(
      repoPathForRemoteActions(settings: settings, projectId: 'p2'),
      'C:\\fallback',
    );
  });

  test('从 origin 读取远端并打开 Actions', () async {
    final result = await openRemoteActionsPage(
      projectId: 'p1',
      settings: const AgentDispatchSettings(
        repoPathByProject: {'p1': 'C:\\repo'},
      ),
      runner: (
        executable,
        arguments, {
        required workingDirectory,
        required environment,
      }) async {
        expect(executable, 'git');
        expect(workingDirectory, 'C:\\repo');
        if (arguments.join(' ') == 'remote get-url origin') {
          return ProcessResult(0, 0, 'git@github.com:acme/kanban.git\n', '');
        }
        fail('unexpected git ${arguments.join(' ')}');
      },
      launcher: (uri) async {
        expect(uri, Uri.parse('https://github.com/acme/kanban/actions'));
        return true;
      },
    );

    expect(result.ok, isTrue);
    expect(result.uri, Uri.parse('https://github.com/acme/kanban/actions'));
  });

  test('没有 origin 时回退到第一个 remote', () async {
    final result = await resolveRemoteActionsUri(
      projectId: null,
      settings: const AgentDispatchSettings(repoPath: '/tmp/repo'),
      runner: (
        executable,
        arguments, {
        required workingDirectory,
        required environment,
      }) async {
        if (arguments.join(' ') == 'remote get-url origin') {
          return ProcessResult(1, 1, '', 'No such remote');
        }
        if (arguments.join(' ') == 'remote') {
          return ProcessResult(0, 0, 'upstream\n', '');
        }
        if (arguments.join(' ') == 'remote get-url upstream') {
          return ProcessResult(
            0,
            0,
            'https://github.com/acme/kanban.git\n',
            '',
          );
        }
        fail('unexpected git ${arguments.join(' ')}');
      },
    );

    expect(result.uri, Uri.parse('https://github.com/acme/kanban/actions'));
  });

  test('未绑定仓库时给出明确错误', () async {
    final result = await resolveRemoteActionsUri(
      projectId: 'p1',
      settings: const AgentDispatchSettings(),
    );

    expect(result.ok, isFalse);
    expect(result.error, contains('未绑定仓库'));
  });
}
