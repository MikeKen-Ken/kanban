import 'dart:convert';
import 'dart:io';

import 'app_update_constants.dart';
import 'github_release_models.dart';

/// 从 GitHub Releases API 拉取已发布的版本列表。
class GithubReleaseClient {
  GithubReleaseClient({
    HttpClient? httpClient,
    this.owner = AppUpdateConstants.owner,
    this.repo = AppUpdateConstants.repo,
  }) : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;
  final String owner;
  final String repo;

  Uri get _releasesUri => Uri.https(
        'api.github.com',
        '/repos/$owner/$repo/releases',
        {'per_page': '10'},
      );

  Future<List<GithubReleaseInfo>> fetchReleases() async {
    final request = await _httpClient.getUrl(_releasesUri);
    request.headers.set(HttpHeaders.userAgentHeader, AppUpdateConstants.userAgent);
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '读取 GitHub Release 失败（HTTP ${response.statusCode}）',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('GitHub Release 响应格式无效');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(GithubReleaseInfo.fromJson)
        .where((r) => !r.draft && r.tagName.isNotEmpty)
        .toList();
  }

  /// 下载到 [destination]，[onProgress] 参数为 0.0–1.0（未知总长时可能为 null）。
  Future<void> downloadAsset(
    GithubReleaseAsset asset,
    File destination, {
    void Function(double? progress)? onProgress,
  }) async {
    final uri = Uri.parse(asset.browserDownloadUrl);
    final request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, AppUpdateConstants.userAgent);
    request.followRedirects = true;
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('下载失败（HTTP ${response.statusCode}）');
    }
    final total = response.contentLength;
    var received = 0;
    final sink = destination.openWrite();
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null) {
          if (total > 0) {
            onProgress(received / total);
          } else {
            onProgress(null);
          }
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  void close() => _httpClient.close(force: true);
}

/// 按平台挑选 Release 资源。
GithubReleaseAsset? pickAssetForPlatform(
  List<GithubReleaseAsset> assets, {
  required bool android,
  required bool windows,
}) {
  final lower = assets.map((a) => (a, a.name.toLowerCase())).toList();
  if (android) {
    for (final (asset, name) in lower) {
      if (name.contains(AppUpdateConstants.androidAssetHint) &&
          name.endsWith('.apk')) {
        return asset;
      }
    }
    for (final (asset, name) in lower) {
      if (name.endsWith('.apk')) return asset;
    }
  }
  if (windows) {
    for (final (asset, name) in lower) {
      if (name.contains(AppUpdateConstants.windowsAssetHint) &&
          name.endsWith('.zip')) {
        return asset;
      }
    }
    for (final (asset, name) in lower) {
      if (name.endsWith('.zip')) return asset;
    }
  }
  return null;
}
