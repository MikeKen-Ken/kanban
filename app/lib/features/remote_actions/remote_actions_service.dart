import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agent_dispatch/agent_dispatch_settings.dart';
import '../mcp/mcp_git_commit.dart';
import 'remote_actions_url.dart';

typedef RemoteActionsLauncher = Future<bool> Function(Uri uri);

class RemoteActionsOpenResult {
  const RemoteActionsOpenResult._({this.uri, this.error});

  factory RemoteActionsOpenResult.ok(Uri uri) =>
      RemoteActionsOpenResult._(uri: uri);

  factory RemoteActionsOpenResult.fail(String error) =>
      RemoteActionsOpenResult._(error: error);

  final Uri? uri;
  final String? error;

  bool get ok => uri != null && error == null;
}

String? repoPathForRemoteActions({
  required AgentDispatchSettings settings,
  required String? projectId,
}) {
  return settings.repoPathFor(projectId);
}

Future<String?> readGitRemoteUrl(
  String repoPath, {
  McpGitRunner? runner,
}) async {
  final repo = repoPath.trim();
  if (repo.isEmpty) return null;
  final run = runner ?? _defaultRunner;
  final origin = await _remoteGetUrl(run, repo, 'origin');
  if (origin != null) return origin;
  final remotes = await run(
    'git',
    ['remote'],
    workingDirectory: repo,
    environment: mcpGitEnvironment(),
  );
  if (remotes.exitCode != 0) return null;
  final names = '${remotes.stdout}'
      .split(RegExp(r'\s+'))
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty);
  for (final name in names) {
    final url = await _remoteGetUrl(run, repo, name);
    if (url != null) return url;
  }
  return null;
}

Future<RemoteActionsOpenResult> resolveRemoteActionsUri({
  required String? projectId,
  AgentDispatchSettings? settings,
  McpGitRunner? runner,
}) async {
  final resolved = settings ??
      (await SharedPreferences.getInstance()).loadAgentDispatchSettings();
  final repoPath = repoPathForRemoteActions(
    settings: resolved,
    projectId: projectId,
  );
  if (repoPath == null) {
    return RemoteActionsOpenResult.fail('当前项目未绑定仓库，请先在 Agent 调度里选择仓库路径');
  }
  final remote = await readGitRemoteUrl(repoPath, runner: runner);
  if (remote == null || remote.isEmpty) {
    return RemoteActionsOpenResult.fail('无法读取仓库远端地址');
  }
  final uri = remoteActionsUri(remote);
  if (uri == null) {
    return RemoteActionsOpenResult.fail('无法识别远端仓库地址：$remote');
  }
  return RemoteActionsOpenResult.ok(uri);
}

Future<RemoteActionsOpenResult> openRemoteActionsPage({
  required String? projectId,
  AgentDispatchSettings? settings,
  McpGitRunner? runner,
  RemoteActionsLauncher? launcher,
}) async {
  final resolved = await resolveRemoteActionsUri(
    projectId: projectId,
    settings: settings,
    runner: runner,
  );
  final uri = resolved.uri;
  if (uri == null) return resolved;
  final launch = launcher ??
      ((target) => launchUrl(target, mode: LaunchMode.externalApplication));
  final opened = await launch(uri);
  if (!opened) {
    return RemoteActionsOpenResult.fail('无法打开远端 Actions：$uri');
  }
  return resolved;
}

Future<String?> _remoteGetUrl(
  McpGitRunner run,
  String repo,
  String name,
) async {
  final result = await run(
    'git',
    ['remote', 'get-url', name],
    workingDirectory: repo,
    environment: mcpGitEnvironment(),
  );
  if (result.exitCode != 0) return null;
  final url = '${result.stdout}'.trim();
  return url.isEmpty ? null : url;
}

Future<ProcessResult> _defaultRunner(
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
