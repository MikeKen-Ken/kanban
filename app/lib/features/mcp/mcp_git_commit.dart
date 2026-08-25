import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/git_commit_ref.dart';

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

/// 一个安全可自动收尾的嵌套 Git 仓库。
///
/// 只接受一个脏 submodule，且父仓库除该 gitlink 外没有其它改动。
class McpSingleDirtySubmodule {
  const McpSingleDirtySubmodule({
    required this.repoPath,
    required this.parentRelativePath,
  });

  final String repoPath;
  final String parentRelativePath;
}

class McpGitRevertOutcome {
  const McpGitRevertOutcome._({required this.ok, this.error});

  factory McpGitRevertOutcome.success() =>
      const McpGitRevertOutcome._(ok: true);

  factory McpGitRevertOutcome.failure(String error) =>
      McpGitRevertOutcome._(ok: false, error: error);

  final bool ok;
  final String? error;
}

const defaultMcpGitAuthorName = 'Kanban Agent';
const defaultMcpGitAuthorEmail = 'kanban-agent@local';
const mcpGitAuthorNamePrefKey = 'mcp_git_author_name';
const mcpGitAuthorEmailPrefKey = 'mcp_git_author_email';

String _gitAuthorName = defaultMcpGitAuthorName;
String _gitAuthorEmail = defaultMcpGitAuthorEmail;

String resolveMcpGitAuthorName(String? name) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? defaultMcpGitAuthorName : trimmed;
}

String resolveMcpGitAuthorEmail(String? email) {
  final trimmed = email?.trim() ?? '';
  return trimmed.isEmpty ? defaultMcpGitAuthorEmail : trimmed;
}

/// 更新本进程 Git 作者身份；空值回退默认。
void applyMcpGitAuthorIdentity({String? name, String? email}) {
  _gitAuthorName = resolveMcpGitAuthorName(name);
  _gitAuthorEmail = resolveMcpGitAuthorEmail(email);
}

Future<void> persistMcpGitAuthorIdentity({
  String? name,
  String? email,
  SharedPreferences? prefs,
}) async {
  final store = prefs ?? await SharedPreferences.getInstance();
  final resolvedName = name?.trim() ?? '';
  final resolvedEmail = email?.trim() ?? '';
  if (resolvedName.isEmpty) {
    await store.remove(mcpGitAuthorNamePrefKey);
  } else {
    await store.setString(mcpGitAuthorNamePrefKey, resolvedName);
  }
  if (resolvedEmail.isEmpty) {
    await store.remove(mcpGitAuthorEmailPrefKey);
  } else {
    await store.setString(mcpGitAuthorEmailPrefKey, resolvedEmail);
  }
  applyMcpGitAuthorIdentity(name: resolvedName, email: resolvedEmail);
}

Future<void> refreshMcpGitAuthorIdentity({
  SharedPreferences? prefs,
}) async {
  final store = prefs ?? await SharedPreferences.getInstance();
  var name = store.getString(mcpGitAuthorNamePrefKey);
  var email = store.getString(mcpGitAuthorEmailPrefKey);
  if ((name == null || name.trim().isEmpty) ||
      (email == null || email.trim().isEmpty)) {
    final raw = store.getString('agent_dispatch_settings');
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        name ??= json['gitAuthorName'] as String?;
        email ??= json['gitAuthorEmail'] as String?;
      } catch (_) {}
    }
  }
  applyMcpGitAuthorIdentity(name: name, email: email);
}

/// `git add -A` 时排除凭据类未跟踪文件，避免写入提交。
const mcpGitAddPathspecs = [
  '.',
  ':(exclude).env',
  ':(exclude).env.*',
  ':(exclude)**/.env',
  ':(exclude)**/.env.*',
  ':(exclude)**/credentials.json',
  ':(exclude)**/*.pem',
  ':(exclude)**/*.key',
  ':(exclude)**/id_rsa',
  ':(exclude)**/id_rsa.pub',
];

Map<String, String> mcpGitEnvironment({
  String? authorName,
  String? authorEmail,
}) {
  final name =
      authorName == null ? _gitAuthorName : resolveMcpGitAuthorName(authorName);
  final email = authorEmail == null
      ? _gitAuthorEmail
      : resolveMcpGitAuthorEmail(authorEmail);
  return {
    ...Platform.environment,
    'GIT_TERMINAL_PROMPT': '0',
    'GCM_INTERACTIVE': 'Never',
    'GIT_AUTHOR_NAME': name,
    'GIT_AUTHOR_EMAIL': email,
    'GIT_COMMITTER_NAME': name,
    'GIT_COMMITTER_EMAIL': email,
  };
}

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

/// `git add -A` 后用临时文件提交，返回 7 位短哈希。
Future<McpGitCommitOutcome> commitMcpWorkingTree({
  required String repoPath,
  required String message,
  List<String> trailers = const [],
  McpGitRunner? runner,
}) async {
  final repo = repoPath.trim();
  final text = message.trim();
  if (repo.isEmpty) {
    return McpGitCommitOutcome.failure('Repository path is required');
  }
  if (text.isEmpty) {
    return McpGitCommitOutcome.failure('Commit message cannot be empty');
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
      'Unable to resolve the Git directory: ${_combinedOutput(gitDir)}',
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
      ['add', '-A', '--', ...mcpGitAddPathspecs],
      workingDirectory: repo,
      environment: mcpGitEnvironment(),
    );
    if (add.exitCode != 0) {
      return McpGitCommitOutcome.failure(
          'git add failed: ${_combinedOutput(add)}');
    }
    final commit = await run(
      'git',
      [
        'commit',
        for (final trailer in trailers) ...['--trailer', trailer],
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
        'git commit failed: ${_combinedOutput(commit)}',
      );
    }
    final hash = await run(
      'git',
      ['rev-parse', '--verify', 'HEAD'],
      workingDirectory: repo,
      environment: mcpGitEnvironment(),
    );
    final commitRef = '${hash.stdout}'.trim();
    if (hash.exitCode != 0 || commitRef.isEmpty) {
      return McpGitCommitOutcome.failure(
        'Unable to read the commit hash: ${_combinedOutput(hash)}',
      );
    }
    return McpGitCommitOutcome.success(abbreviateGitCommitRef(commitRef));
  } finally {
    if (await messageFile.exists()) {
      await messageFile.delete();
    }
  }
}

/// 仅由 Worker 调用。失败时尽力 abort，避免把冲突状态留给下一轮。
Future<McpGitRevertOutcome> revertMcpCommitWithoutCommit({
  required String repoPath,
  required String commitRef,
  McpGitRunner? runner,
}) async {
  final repo = repoPath.trim();
  final target = commitRef.trim();
  if (repo.isEmpty || !RegExp(r'^[0-9a-fA-F]{7,64}$').hasMatch(target)) {
    return McpGitRevertOutcome.failure(
        'The revert target must be a valid Git commit hash');
  }
  final run = runner ?? _defaultGitRunner;
  final result = await run(
    'git',
    ['revert', '--no-commit', target],
    workingDirectory: repo,
    environment: mcpGitEnvironment(),
  );
  if (result.exitCode == 0) return McpGitRevertOutcome.success();

  final aborted = await run(
    'git',
    ['revert', '--abort'],
    workingDirectory: repo,
    environment: mcpGitEnvironment(),
  );
  final abortHint = aborted.exitCode == 0
      ? '; the pre-revert state was restored'
      : '; automatic recovery failed, inspect the Git state manually: ${_combinedOutput(aborted)}';
  return McpGitRevertOutcome.failure(
    'git revert failed: ${_combinedOutput(result)}$abortHint',
  );
}

Future<void> abortMcpGitRevert({
  required String repoPath,
  McpGitRunner? runner,
}) async {
  final run = runner ?? _defaultGitRunner;
  await run(
    'git',
    ['revert', '--abort'],
    workingDirectory: repoPath.trim(),
    environment: mcpGitEnvironment(),
  );
}

Future<List<String>?> listMcpGitChangedPaths(
  String repoPath, {
  McpGitRunner? runner,
}) async {
  final run = runner ?? _defaultGitRunner;
  final result = await run(
    'git',
    ['status', '--porcelain=v1', '-z'],
    workingDirectory: repoPath.trim(),
    environment: mcpGitEnvironment(),
  );
  if (result.exitCode != 0) return null;
  return parseMcpGitPorcelainZ('${result.stdout}');
}

/// 在父仓库中找出唯一发生改动的直接 submodule。
///
/// `null` 代表没有可安全自动处理的唯一候选；调用方应保持原有单仓库
/// 收尾或显示人工处理提示，绝不猜测多个嵌套仓库的提交范围。
Future<McpSingleDirtySubmodule?> findMcpSingleDirtySubmodule(
  String repoPath, {
  McpGitRunner? runner,
}) async {
  final repo = repoPath.trim();
  if (repo.isEmpty) return null;
  final run = runner ?? _defaultGitRunner;
  final listed = await run(
    'git',
    [
      'config',
      '--file',
      '.gitmodules',
      '--get-regexp',
      r'^submodule\..*\.path$'
    ],
    workingDirectory: repo,
    environment: mcpGitEnvironment(),
  );
  // exit 1 means this checkout has no .gitmodules/path entries.
  if (listed.exitCode != 0) return null;
  final candidates = <McpSingleDirtySubmodule>[];
  for (final line in '${listed.stdout}'.split(RegExp(r'\r?\n'))) {
    final separator = line.indexOf(RegExp(r'\s'));
    if (separator < 0) continue;
    final relativePath = _normalizeGitPath(line.substring(separator).trim());
    if (relativePath.isEmpty) continue;
    final childPath = p.normalize(p.join(repo, relativePath));
    final child = await inspectMcpGitTree(childPath, runner: runner);
    if (child.kind == McpGitTreeKind.dirty) {
      candidates.add(McpSingleDirtySubmodule(
        repoPath: childPath,
        parentRelativePath: relativePath,
      ));
    }
  }
  if (candidates.length != 1) return null;
  final parentPaths = await listMcpGitChangedPaths(repo, runner: runner);
  final candidate = candidates.single;
  if (parentPaths == null ||
      parentPaths.length != 1 ||
      parentPaths.single != candidate.parentRelativePath) {
    return null;
  }
  return candidate;
}

/// 解析 `git status --porcelain=v1 -z`。rename/copy 的源路径是独立 NUL 字段，没有 `XY ` 前缀。
List<String> parseMcpGitPorcelainZ(String raw) {
  final entries = raw.split('\x00');
  final paths = <String>[];
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    if (entry.length < 3) continue;
    final xy = entry.substring(0, 2);
    final path = _normalizeGitPath(
      entry.length > 3 ? entry.substring(3) : '',
    );
    if (path.isNotEmpty) paths.add(path);
    final kind = xy.isEmpty ? '' : xy[0];
    if (kind != 'R' && kind != 'C') continue;
    index += 1;
    if (index >= entries.length) break;
    final source = _normalizeGitPath(entries[index]);
    if (source.isNotEmpty) paths.add(source);
  }
  return paths;
}

String _normalizeGitPath(String path) => path.trim().replaceAll('\\', '/');

bool isMcpSensitiveGitPath(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  final segments = normalized.split('/');
  final name = segments.isEmpty ? normalized : segments.last;
  return name == '.env' ||
      name.startsWith('.env.') ||
      name == 'credentials.json' ||
      name == 'auth.json' ||
      name == 'id_rsa' ||
      name == 'id_rsa.pub' ||
      name.endsWith('.pem') ||
      name.endsWith('.key') ||
      name.endsWith('.p12') ||
      name.endsWith('.pfx') ||
      segments.contains('secrets');
}

Future<String?> findMcpCommitByDispatchTrailers({
  required String repoPath,
  required String sessionId,
  required String cardId,
  McpGitRunner? runner,
}) async {
  final run = runner ?? _defaultGitRunner;
  final result = await run(
    'git',
    [
      'log',
      '-1',
      '--format=%H',
      '--all-match',
      '--fixed-strings',
      '--grep=Kanban-Session: $sessionId',
      '--grep=Kanban-Card: $cardId',
    ],
    workingDirectory: repoPath.trim(),
    environment: mcpGitEnvironment(),
  );
  if (result.exitCode != 0) return null;
  final value = '${result.stdout}'.trim();
  return value.isEmpty ? null : abbreviateGitCommitRef(value);
}

/// 读取当前 HEAD 的完整提交哈希，与 `git log` / Git 客户端显示一致。
Future<String?> mcpGitHeadHash(
  String repoPath, {
  McpGitRunner? runner,
}) async {
  final run = runner ?? _defaultGitRunner;
  final hash = await run(
    'git',
    ['rev-parse', '--verify', 'HEAD'],
    workingDirectory: repoPath.trim(),
    environment: mcpGitEnvironment(),
  );
  if (hash.exitCode != 0) return null;
  final value = '${hash.stdout}'.trim();
  return value.isEmpty ? null : value;
}

enum McpGitBaselineRestoreKind { unchanged, restored, unrelated, failed }

/// Agent 超前提交后，把 HEAD 软复位到领取 baseline 的结果。
class McpGitBaselineRestore {
  const McpGitBaselineRestore._({required this.kind, this.error});

  factory McpGitBaselineRestore.unchanged() => const McpGitBaselineRestore._(
        kind: McpGitBaselineRestoreKind.unchanged,
      );

  factory McpGitBaselineRestore.restored() => const McpGitBaselineRestore._(
        kind: McpGitBaselineRestoreKind.restored,
      );

  factory McpGitBaselineRestore.unrelated({
    required String baseline,
    required String head,
  }) =>
      McpGitBaselineRestore._(
        kind: McpGitBaselineRestoreKind.unrelated,
        error: 'The Agent moved HEAD: baseline=$baseline, HEAD=$head',
      );

  factory McpGitBaselineRestore.failed(String error) =>
      McpGitBaselineRestore._(
        kind: McpGitBaselineRestoreKind.failed,
        error: error,
      );

  final McpGitBaselineRestoreKind kind;
  final String? error;

  bool get ok =>
      kind == McpGitBaselineRestoreKind.unchanged ||
      kind == McpGitBaselineRestoreKind.restored;
}

/// 若 HEAD 仍等于 [baseline] 则不动。
/// 若 [baseline] 是 HEAD 的祖先，则 `git reset --soft` 回到 baseline，
/// 把 Agent 自行提交的内容留在暂存区，供 Worker 统一带 trailer 提交。
/// checkout / rebase 到无关历史时拒绝。
Future<McpGitBaselineRestore> restoreMcpGitBaselineIfDescendant({
  required String repoPath,
  required String baseline,
  McpGitRunner? runner,
}) async {
  final repo = repoPath.trim();
  final base = baseline.trim();
  if (repo.isEmpty || base.isEmpty) {
    return McpGitBaselineRestore.failed('Git baseline is missing');
  }
  final head = await mcpGitHeadHash(repo, runner: runner);
  if (head == null || head.isEmpty) {
    return McpGitBaselineRestore.failed('Unable to read HEAD');
  }
  if (head == base) return McpGitBaselineRestore.unchanged();

  final run = runner ?? _defaultGitRunner;
  final ancestor = await run(
    'git',
    ['merge-base', '--is-ancestor', base, head],
    workingDirectory: repo,
    environment: mcpGitEnvironment(),
  );
  if (ancestor.exitCode != 0) {
    if (ancestor.exitCode == 1) {
      return McpGitBaselineRestore.unrelated(baseline: base, head: head);
    }
    return McpGitBaselineRestore.failed(
      'Unable to compare HEAD with the claim baseline: ${_combinedOutput(ancestor)}',
    );
  }

  final reset = await run(
    'git',
    ['reset', '--soft', base],
    workingDirectory: repo,
    environment: mcpGitEnvironment(),
  );
  if (reset.exitCode != 0) {
    return McpGitBaselineRestore.failed(
      'git reset --soft failed: ${_combinedOutput(reset)}',
    );
  }
  final restoredHead = await mcpGitHeadHash(repo, runner: runner);
  if (restoredHead != base) {
    return McpGitBaselineRestore.failed(
      'HEAD was not restored to the claim baseline: expected=$base, HEAD=$restoredHead',
    );
  }
  return McpGitBaselineRestore.restored();
}
