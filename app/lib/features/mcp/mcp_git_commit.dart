import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 调度收尾用的 Git 探测与提交；不 push。
typedef McpGitRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Map<String, String> environment,
});

enum McpGitTreeKind { notGit, clean, dirty }

class McpGitTree {
  const McpGitTree({required this.kind, this.output = ''});

  final McpGitTreeKind kind;
  final String output;

  bool get isGit => kind != McpGitTreeKind.notGit;
}

class McpGitCommitOutcome {
  const McpGitCommitOutcome._({
    required this.ok,
    this.commitRef,
    this.error,
  });

  factory McpGitCommitOutcome.success(String commitRef) =>
      McpGitCommitOutcome._(ok: true, commitRef: commitRef);

  factory McpGitCommitOutcome.failure(String error) =>
      McpGitCommitOutcome._(ok: false, error: error);

  final bool ok;
  final String? commitRef;
  final String? error;
}

const _gitEnv = {
  'GIT_TERMINAL_PROMPT': '0',
  'GCM_INTERACTIVE': 'Never',
  'GIT_AUTHOR_NAME': 'Kanban Agent',
  'GIT_AUTHOR_EMAIL': 'kanban-agent@local',
  'GIT_COMMITTER_NAME': 'Kanban Agent',
  'GIT_COMMITTER_EMAIL': 'kanban-agent@local',
};

Map<String, String> mcpGitEnvironment() => {
      ...Platform.environment,
      ..._gitEnv,
    };

Future<ProcessResult> _defaultGitRunner(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Map<String, String> environment,
}) {
  return Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: false,
  );
}

String _combinedOutput(ProcessResult result) {
  final stdout = '${result.stdout}'.trim();
  final stderr = '${result.stderr}'.trim();
  if (stdout.isEmpty) return stderr;
  if (stderr.isEmpty) return stdout;
  return '$stdout\n$stderr';
}

bool _looksLikeNotGit(String text) {
  final lower = text.toLowerCase();
  return lower.contains('not a git repository') ||
      lower.contains('不是 git 仓库') ||
      lower.contains('not a git repo');
}

/// 与 Skill 原先的 `git status --short` 语义一致。
Future<McpGitTree> inspectMcpGitTree(
  String repoPath, {
  McpGitRunner? runner,
}) async {
  final repo = repoPath.trim();
  if (repo.isEmpty) return const McpGitTree(kind: McpGitTreeKind.notGit);
  final run = runner ?? _defaultGitRunner;
  final result = await run(
    'git',
    ['status', '--short'],
    workingDirectory: repo,
    environment: mcpGitEnvironment(),
  );
  final output = _combinedOutput(result);
  if (result.exitCode != 0) {
    if (_looksLikeNotGit(output) || result.exitCode == 128) {
      return const McpGitTree(kind: McpGitTreeKind.notGit);
    }
    return McpGitTree(kind: McpGitTreeKind.dirty, output: output);
  }
  if (output.isEmpty) return const McpGitTree(kind: McpGitTreeKind.clean);
  return McpGitTree(kind: McpGitTreeKind.dirty, output: output);
}

/// `git add -A` 后用临时文件提交，返回短 hash。
Future<McpGitCommitOutcome> commitMcpWorkingTree({
  required String repoPath,
  required String message,
  McpGitRunner? runner,
}) async {
  final repo = repoPath.trim();
  final text = message.trim();
  if (repo.isEmpty) {
    return McpGitCommitOutcome.failure('缺少仓库路径');
  }
  if (text.isEmpty) {
    return McpGitCommitOutcome.failure('提交信息不能为空');
  }
  final run = runner ?? _defaultGitRunner;
  final gitDir = await run(
    'git',
    ['rev-parse', '--git-dir'],
    workingDirectory: repo,
    environment: mcpGitEnvironment(),
  );
  if (gitDir.exitCode != 0) {
    return McpGitCommitOutcome.failure(
      '无法解析 Git 目录：${_combinedOutput(gitDir)}',
    );
  }
  var gitDirPath = '${gitDir.stdout}'.trim();
  if (!p.isAbsolute(gitDirPath)) {
    gitDirPath = p.join(repo, gitDirPath);
  }
  final messageFile = File(
    p.join(
      gitDirPath,
      'KANBAN_COMMIT_MESSAGE_${DateTime.now().microsecondsSinceEpoch}.txt',
    ),
  );
  try {
    await messageFile.writeAsBytes(utf8.encode(text), flush: true);
    final add = await run(
      'git',
      ['add', '-A'],
      workingDirectory: repo,
      environment: mcpGitEnvironment(),
    );
    if (add.exitCode != 0) {
      return McpGitCommitOutcome.failure('git add 失败：${_combinedOutput(add)}');
    }
    final commit = await run(
      'git',
      [
        'commit',
        '--trailer',
        'Co-authored-by: Cursor <cursoragent@cursor.com>',
        '-F',
        messageFile.path,
      ],
      workingDirectory: repo,
      environment: mcpGitEnvironment(),
    );
    if (commit.exitCode != 0) {
      return McpGitCommitOutcome.failure(
        'git commit 失败：${_combinedOutput(commit)}',
      );
    }
    final hash = await run(
      'git',
      ['rev-parse', '--short', 'HEAD'],
      workingDirectory: repo,
      environment: mcpGitEnvironment(),
    );
    final commitRef = '${hash.stdout}'.trim();
    if (hash.exitCode != 0 || commitRef.isEmpty) {
      return McpGitCommitOutcome.failure(
        '无法读取提交号：${_combinedOutput(hash)}',
      );
    }
    return McpGitCommitOutcome.success(commitRef);
  } finally {
    if (await messageFile.exists()) {
      await messageFile.delete();
    }
  }
}

Future<String?> mcpGitShortHead(
  String repoPath, {
  McpGitRunner? runner,
}) async {
  final run = runner ?? _defaultGitRunner;
  final hash = await run(
    'git',
    ['rev-parse', '--short', 'HEAD'],
    workingDirectory: repoPath.trim(),
    environment: mcpGitEnvironment(),
  );
  if (hash.exitCode != 0) return null;
  final value = '${hash.stdout}'.trim();
  return value.isEmpty ? null : value;
}
