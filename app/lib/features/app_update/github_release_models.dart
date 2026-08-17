import 'package:intl/intl.dart';

import 'release_notes_plain_text.dart';

/// 将 GitHub 时间转为本地可读日期；无值时返回空串。
String formatAppUpdateDate(DateTime? value) {
  if (value == null) return '';
  return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
}

/// GitHub Release 摘要（仅更新所需字段）。
class GithubReleaseInfo {
  const GithubReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.draft,
    required this.prerelease,
    required this.publishedAt,
    required this.assets,
  });

  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final bool draft;
  final bool prerelease;
  final DateTime? publishedAt;
  final List<GithubReleaseAsset> assets;

  /// 去掉 `v` 前缀后的版本号。
  String get versionLabel {
    final tag = tagName.trim();
    if (tag.startsWith('v') || tag.startsWith('V')) {
      return tag.substring(1);
    }
    return tag;
  }

  /// 用于展示的发布时间：Release `published_at`，否则取资源 `updated_at`。
  DateTime? get displayDate {
    if (publishedAt != null) return publishedAt;
    for (final asset in assets) {
      if (asset.updatedAt != null) return asset.updatedAt;
    }
    return null;
  }

  factory GithubReleaseInfo.fromJson(Map<String, dynamic> json) {
    final assetsRaw = json['assets'] as List<dynamic>? ?? const [];
    return GithubReleaseInfo(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: releaseNotesToPlainText(json['body'] as String? ?? ''),
      htmlUrl: json['html_url'] as String? ?? '',
      draft: json['draft'] as bool? ?? false,
      prerelease: json['prerelease'] as bool? ?? false,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      assets: assetsRaw
          .whereType<Map<String, dynamic>>()
          .map(GithubReleaseAsset.fromJson)
          .toList(),
    );
  }
}

class GithubReleaseAsset {
  const GithubReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.size,
    required this.updatedAt,
  });

  final String name;
  final String browserDownloadUrl;
  final int size;
  final DateTime? updatedAt;

  factory GithubReleaseAsset.fromJson(Map<String, dynamic> json) {
    return GithubReleaseAsset(
      name: json['name'] as String? ?? '',
      browserDownloadUrl: json['browser_download_url'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }
}

/// 检测结果：有无可用更新。
class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.currentBuild,
    this.release,
    this.asset,
    this.updateAvailable = false,
    this.message,
  });

  final String currentVersion;
  final String currentBuild;
  final GithubReleaseInfo? release;
  final GithubReleaseAsset? asset;
  final bool updateAvailable;
  final String? message;
}
