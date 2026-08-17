/// 把 git remote 地址转成托管平台的 Actions / CI 列表页。
Uri? remoteActionsUri(String remoteUrl) {
  final https = _asHttpsUri(remoteUrl.trim());
  if (https == null) return null;
  final host = https.host;
  if (host.isEmpty) return null;
  final repoPath = _ownerRepoPath(https.path);
  if (repoPath == null) return null;
  final hostLower = host.toLowerCase();
  if (hostLower.contains('gitlab')) {
    return Uri.https(host, '/$repoPath/-/pipelines');
  }
  if (hostLower.contains('bitbucket')) {
    return Uri.https(host, '/$repoPath/pipelines');
  }
  return Uri.https(host, '/$repoPath/actions');
}

Uri? _asHttpsUri(String raw) {
  if (raw.isEmpty) return null;
  if (raw.contains('\\')) return null;
  if (raw.contains('://')) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    return Uri(scheme: 'https', host: uri.host, path: uri.path);
  }
  final scp = RegExp(r'^(?:[^@/\s]+@)?([^:/\s]+):(.+)$');
  final match = scp.firstMatch(raw);
  if (match == null) return null;
  final host = match.group(1)!;
  final path = match.group(2)!;
  if (host.length == 1 && RegExp(r'^[A-Za-z]$').hasMatch(host)) return null;
  return Uri(scheme: 'https', host: host, path: path);
}

String? _ownerRepoPath(String rawPath) {
  var path = rawPath.trim();
  if (path.endsWith('.git')) {
    path = path.substring(0, path.length - 4);
  }
  path = path.replaceAll(RegExp(r'/+$'), '');
  if (path.startsWith('/')) path = path.substring(1);
  if (path.isEmpty) return null;
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length < 2) return null;
  return parts.join('/');
}
