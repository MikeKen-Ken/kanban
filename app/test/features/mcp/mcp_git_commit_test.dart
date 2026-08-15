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

  test('commitMcpWorkingTree 提交后返回短 hash', () async {
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
    );
    expect(result.ok, isTrue, reason: result.error);
    expect(result.commitRef, isNotEmpty);
    expect(
      (await inspectMcpGitTree(temp.path)).kind,
      McpGitTreeKind.clean,
    );
    expect(await mcpGitShortHead(temp.path), result.commitRef);
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
}
