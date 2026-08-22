import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_constants.dart';
import 'app_update_installer.dart';
import 'github_release_client.dart';
import 'github_release_models.dart';
import 'version_compare.dart';

/// 检查、下载并安装来自 GitHub Release 的更新。
class AppUpdateService {
  AppUpdateService({
    GithubReleaseClient? client,
    AppUpdateInstaller? installer,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<SharedPreferences> Function()? prefsLoader,
  })  : _client = client ?? GithubReleaseClient(),
        _installer = installer ?? AppUpdateInstaller(),
        _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
        _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  final GithubReleaseClient _client;
  final AppUpdateInstaller _installer;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final Future<SharedPreferences> Function() _prefsLoader;

  bool get isSupported => _installer.isSupported;

  Future<AppUpdateCheckResult> checkForUpdate() async {
    final info = await _packageInfoLoader();
    final currentVersion = info.version;
    final currentBuild = info.buildNumber;

    if (!isSupported) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        message: 'In-app updates are not supported on this platform',
      );
    }

    final releases = await _client.fetchReleases();
    final published = releases.where((r) => !r.prerelease).toList();
    final pool = published.isNotEmpty ? published : releases;
    if (pool.isEmpty) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        message: 'No published release is available (drafts are not visible to clients)',
      );
    }

    // GitHub/Atom/jsDelivr usually return newest first, but that is not a
    // contract.  Selecting by version prevents an older feed entry from
    // masking a newer release such as 1.0.143.
    pool.sort(
      (left, right) =>
          VersionCompare.compare(right.versionLabel, left.versionLabel),
    );
    final release = pool.first;
    final asset = await _client.resolvePlatformAsset(
      release,
      android: !kIsWeb && Platform.isAndroid,
      windows: !kIsWeb && Platform.isWindows,
    );
    if (asset == null) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        release: release,
        message: 'This release has no installer for the current platform',
      );
    }

    final newer = VersionCompare.isNewer(release.versionLabel, currentVersion);
    final rebuilt = await _isSameVersionNewerAsset(release.versionLabel, asset);
    final updateAvailable = newer || rebuilt;

    return AppUpdateCheckResult(
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      release: release,
      asset: asset,
      updateAvailable: updateAvailable,
      message: updateAvailable
          ? (newer
              ? 'New version available: ${_versionWithDate(release, asset)}'
              : 'Same-version package refreshed${_optionalDateSuffix(asset.updatedAt ?? release.displayDate)}')
          : 'Up to date${_optionalDateSuffix(release.displayDate)}',
    );
  }

  static String _versionWithDate(
    GithubReleaseInfo release,
    GithubReleaseAsset asset,
  ) {
    final date = formatAppUpdateDate(release.displayDate ?? asset.updatedAt);
    if (date.isEmpty) return release.versionLabel;
    return '${release.versionLabel} ($date)';
  }

  static String _optionalDateSuffix(DateTime? value) {
    final date = formatAppUpdateDate(value);
    if (date.isEmpty) return '';
    return '（$date）';
  }

  Future<bool> _isSameVersionNewerAsset(
    String remoteVersion,
    GithubReleaseAsset asset,
  ) async {
    if (VersionCompare.compare(
            remoteVersion, (await _packageInfoLoader()).version) !=
        0) {
      return false;
    }
    final updatedAt = asset.updatedAt;
    if (updatedAt == null) return false;
    final prefs = await _prefsLoader();
    final raw = prefs.getString(AppUpdateConstants.prefsLastAssetUpdatedAt);
    if (raw == null || raw.isEmpty) {
      // 首次：同版本不提示，避免刚装完就再下一次
      return false;
    }
    final last = DateTime.tryParse(raw);
    if (last == null) return false;
    return updatedAt.isAfter(last);
  }

  Future<void> markAssetInstalled(
    GithubReleaseAsset asset, {
    DateTime? publishedAt,
  }) async {
    final prefs = await _prefsLoader();
    final stamp = (asset.updatedAt ?? DateTime.now().toUtc()).toIso8601String();
    await prefs.setString(AppUpdateConstants.prefsLastAssetUpdatedAt, stamp);
    final published = publishedAt ?? asset.updatedAt;
    if (published != null) {
      await prefs.setString(
        AppUpdateConstants.prefsLastReleasePublishedAt,
        published.toUtc().toIso8601String(),
      );
    }
  }

  Future<DateTime?> installedReleasePublishedAt() async {
    final prefs = await _prefsLoader();
    final raw = prefs.getString(AppUpdateConstants.prefsLastReleasePublishedAt);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> skipVersion(String version) async {
    final prefs = await _prefsLoader();
    await prefs.setString(AppUpdateConstants.prefsSkippedVersion, version);
  }

  Future<String?> skippedVersion() async {
    final prefs = await _prefsLoader();
    return prefs.getString(AppUpdateConstants.prefsSkippedVersion);
  }

  /// 下载并安装；Windows 成功时进程会退出。
  ///
  /// 若本地已有完整安装包（例如 Android 已下载但未完成安装），则跳过下载直接安装。
  Future<void> downloadAndInstall(
    AppUpdateCheckResult check, {
    void Function(double? progress)? onProgress,
  }) async {
    final release = check.release;
    final asset = check.asset;
    if (release == null || asset == null || !check.updateAvailable) {
      throw StateError('No installable update is available');
    }

    final tempDir = await getTemporaryDirectory();
    final downloadPath = p.join(
      tempDir.path,
      localDownloadFileName(release, asset),
    );
    final file = File(downloadPath);
    if (!await _ensureLocalPackage(file, asset)) {
      await _downloadToCompleteFile(file, asset, onProgress: onProgress);
    } else {
      onProgress?.call(1.0);
    }

    if (!kIsWeb && Platform.isAndroid) {
      await _installer.installAndroidApk(file);
      await markAssetInstalled(asset, publishedAt: release.publishedAt);
      return;
    }

    if (!kIsWeb && Platform.isWindows) {
      final extracted = await _installer.extractZip(file);
      await markAssetInstalled(asset, publishedAt: release.publishedAt);
      // 不会返回：进程退出
      await _installer.applyWindowsZipUpdate(extracted);
      return;
    }

    throw UnsupportedError('Automatic installation is not supported on this platform');
  }

  /// 本地是否已有可直接安装的完整包。
  Future<bool> _ensureLocalPackage(
    File file,
    GithubReleaseAsset asset,
  ) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    return isReusableDownloadedPackage(
      exists: true,
      length: length,
      expectedSize: asset.size,
    );
  }

  /// 先下到 `.partial`，成功后再改名为正式文件，避免半成品被当成完整包。
  Future<void> _downloadToCompleteFile(
    File file,
    GithubReleaseAsset asset, {
    void Function(double? progress)? onProgress,
  }) async {
    if (await file.exists()) {
      await file.delete();
    }
    final partial = File('${file.path}.partial');
    if (await partial.exists()) {
      await partial.delete();
    }
    await _client.downloadAsset(asset, partial, onProgress: onProgress);
    await partial.rename(file.path);
  }

  /// 本地安装包是否可跳过重新下载直接安装。
  @visibleForTesting
  static String localDownloadFileName(
    GithubReleaseInfo release,
    GithubReleaseAsset asset,
  ) {
    final releaseKey = release.versionLabel.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final assetKey = asset.name.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    return 'kanban_download_${releaseKey}_$assetKey';
  }

  @visibleForTesting
  static bool isReusableDownloadedPackage({
    required bool exists,
    required int length,
    required int expectedSize,
  }) {
    if (!exists || length <= 0) return false;
    if (expectedSize > 0) return length == expectedSize;
    // 远端 size 未知（如 HEAD 解析路径）时，非空正式文件视为可复用。
    return true;
  }

  void dispose() => _client.close();
}
