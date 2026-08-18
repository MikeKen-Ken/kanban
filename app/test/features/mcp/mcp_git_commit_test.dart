import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/mcp_git_commit.dart';
import 'package:path/path.dart' as p;

Future<void> _git(String repo, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: repo,
    environment: mcpGitEnvironment(),
  );
  if (result.exitCode != 0) {
    fail('git ${args.join(' ')} 失败：${result.stdout}\n${result.stderr}');
  }
}

void main() {
  test('mcpGitEnvironment 使用配置的提交作者身份', () {
    applyMcpGitAuthorIdentity(
      name: '张三',
      email: 'zhangsan@example.com',
    );
    addTearDown(applyMcpGitAuthorIdentity);

    final environment = mcpGitEnvironment();

    expect(environment['GIT_AUTHOR_NAME'], '张三');
    expect(environment['GIT_AUTHOR_EMAIL'], 'zhangsan@example.com');
    expect(environment['GIT_COMMITTER_NAME'], '张三');
    expect(environment['GIT_COMMITTER_EMAIL'], 'zhangsan@example.com');
  });

  test('inspectMcpGitTree 能区分干净、脏与非仓库', () async {
    final temp = await Directory.systemTemp.createTemp('kanban_git_tree_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    expect(
      (await inspectMcpGitTree(temp.path)).kind,
      McpGitTreeKind.notGit,
    );

    await _git(temp.path, ['init']);
    await _git(temp.path, ['config', 'user.email', 'test@example.com']);
    await _git(temp.path, ['config', 'user.name', 'Test']);
    File(p.join(temp.path, 'README.md')).writeAsStringSync('a\n');
    await _git(temp.path, ['add', '-A']);
    await _git(temp.path, ['commit', '-m', 'init']);

    expect(
      (await inspectMcpGitTree(temp.path)).kind,
      McpGitTreeKind.clean,
    );

    File(p.join(temp.path, 'README.md')).writeAsStringSync('b\n');
    expect(
      (await inspectMcpGitTree(temp.path)).kind,
      McpGitTreeKind.dirty,
    );
  });

  test('commitMcpWorkingTree 提交后返回 7 位短哈希', () async {
    final temp = await Directory.systemTemp.createTemp('kanban_git_commit_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    await _git(temp.path, ['init']);
    await _git(temp.path, ['config', 'user.email', 'test@example.com']);
    await _git(temp.path, ['config', 'user.name', 'Test']);
    File(p.join(temp.path, 'a.txt')).writeAsStringSync('one\n');
    await _git(temp.path, ['add', '-A']);
    await _git(temp.path, ['commit', '-m', 'init']);
    File(p.join(temp.path, 'a.txt')).writeAsStringSync('two\n');

    final result = await commitMcpWorkingTree(
      repoPath: temp.path,
      message: '更新 a.txt',
      trailers: const [
        'Kanban-Session: session-a',
        'Kanban-Card: card-a',
      ],
    );
    expect(result.ok, isTrue, reason: result.error);
    expect(result.commitRef, isNotEmpty);
    expect(
      (await inspectMcpGitTree(temp.path)).kind,
      McpGitTreeKind.clean,
    );
    final fullHash = await mcpGitHeadHash(temp.path);
    expect(fullHash, isNotNull);
    expect(result.commitRef, matches(RegExp(r'^[0-9a-f]{7}$')));
    expect(fullHash!.startsWith(result.commitRef!), isTrue);
    expect(
      await findMcpCommitByDispatchTrailers(
        repoPath: temp.path,
        sessionId: 'session-a',
        cardId: 'card-a',
      ),
      result.commitRef,
    );
  });

  test('commitMcpWorkingTree 不把 .env 纳入提交', () async {
    final temp = await Directory.systemTemp.createTemp('kanban_git_secret_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    await _git(temp.path, ['init']);
    await _git(temp.path, ['config', 'user.email', 'test@example.com']);
    await _git(temp.path, ['config', 'user.name', 'Test']);
    File(p.join(temp.path, 'a.txt')).writeAsStringSync('one\n');
    await _git(temp.path, ['add', '-A']);
    await _git(temp.path, ['commit', '-m', 'init']);
    File(p.join(temp.path, 'a.txt')).writeAsStringSync('two\n');
    File(p.join(temp.path, '.env')).writeAsStringSync('SECRET=1\n');

    final result = await commitMcpWorkingTree(
      repoPath: temp.path,
      message: '更新 a.txt',
    );
    expect(result.ok, isTrue, reason: result.error);
    final tracked = await Process.run(
      'git',
      ['ls-files', '.env'],
      workingDirectory: temp.path,
      environment: mcpGitEnvironment(),
    );
    expect('${tracked.stdout}'.trim(), isEmpty);
    expect(
      (await inspectMcpGitTree(temp.path)).kind,
      McpGitTreeKind.dirty,
    );
  });

  test('isMcpSensitiveGitPath 识别凭据与私钥路径', () {
    expect(isMcpSensitiveGitPath('.env'), isTrue);
    expect(isMcpSensitiveGitPath('app/.env.local'), isTrue);
    expect(isMcpSensitiveGitPath('secrets/token.txt'), isTrue);
    expect(isMcpSensitiveGitPath('id_rsa'), isTrue);
    expect(isMcpSensitiveGitPath('lib/main.dart'), isFalse);
  });

  test('parseMcpGitPorcelainZ 把 rename 源路径当作独立字段', () {
    final raw = [
      'R  notes.md',
      '.env',
      'C  backup/id_rsa',
      'id_rsa',
      ' M lib/main.dart',
      '?? extra.txt',
      '',
    ].join('\x00');
    expect(parseMcpGitPorcelainZ(raw), [
      'notes.md',
      '.env',
      'backup/id_rsa',
      'id_rsa',
      'lib/main.dart',
      'extra.txt',
    ]);
    final paths = parseMcpGitPorcelainZ(raw);
    expect(paths.where(isMcpSensitiveGitPath), [
      '.env',
      'backup/id_rsa',
      'id_rsa',
    ]);
  });
}
