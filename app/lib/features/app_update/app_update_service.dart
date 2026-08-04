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
        message: '当前平台不支持软件内更新',
      );
    }

    final releases = await _client.fetchReleases();
    final published = releases.where((r) => !r.prerelease).toList();
    final pool = published.isNotEmpty ? published : releases;
    if (pool.isEmpty) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        message: '没有已发布的正式 Release（草稿对客户端不可见）',
      );
    }

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
        message: '该 Release 没有适合当前平台的安装包',
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
              ? '发现新版本 ${release.versionLabel}'
              : '发现同版本更新包（构建已刷新）')
          : '已是最新版本',
    );
  }

  Future<bool> _isSameVersionNewerAsset(
    String remoteVersion,
    GithubReleaseAsset asset,
  ) async {
    if (VersionCompare.compare(remoteVersion, (await _packageInfoLoader()).version) !=
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

  Future<void> markAssetInstalled(GithubReleaseAsset asset) async {
    final prefs = await _prefsLoader();
    final stamp = (asset.updatedAt ?? DateTime.now().toUtc()).toIso8601String();
    await prefs.setString(AppUpdateConstants.prefsLastAssetUpdatedAt, stamp);
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
  Future<void> downloadAndInstall(
    AppUpdateCheckResult check, {
    void Function(double? progress)? onProgress,
  }) async {
    final release = check.release;
    final asset = check.asset;
    if (release == null || asset == null || !check.updateAvailable) {
      throw StateError('没有可安装的更新');
    }

    final tempDir = await getTemporaryDirectory();
    final downloadPath = p.join(
      tempDir.path,
      'kanban_download_${asset.name}',
    );
    final file = File(downloadPath);
    if (await file.exists()) {
      await file.delete();
    }

    await _client.downloadAsset(asset, file, onProgress: onProgress);

    if (!kIsWeb && Platform.isAndroid) {
      await _installer.installAndroidApk(file);
      await markAssetInstalled(asset);
      return;
    }

    if (!kIsWeb && Platform.isWindows) {
      final extracted = await _installer.extractZip(file);
      await markAssetInstalled(asset);
      // 不会返回：进程退出
      await _installer.applyWindowsZipUpdate(extracted);
      return;
    }

    throw UnsupportedError('当前平台不支持自动安装');
  }

  void dispose() => _client.close();
}
