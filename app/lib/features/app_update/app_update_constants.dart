/// GitHub Release 更新源与本地偏好键。
class AppUpdateConstants {
  AppUpdateConstants._();

  static const owner = 'MikeKen-Ken';
  static const repo = 'kanban';
  static const userAgent = 'KanbanApp-Updater';

  /// 已成功安装的包资源 `updated_at`（ISO8601），用于同版本覆盖包检测。
  static const prefsLastAssetUpdatedAt = 'app_update_last_asset_updated_at';

  /// 已成功安装的 Release `published_at`（ISO8601），用于「当前版本」展示日期。
  static const prefsLastReleasePublishedAt =
      'app_update_last_release_published_at';

  /// 与 [prefsLastReleasePublishedAt] 配对的版本号；不匹配时忽略本地日期。
  static const prefsLastReleaseVersion = 'app_update_last_release_version';

  /// 用户跳过的版本号，启动时不再提示。
  static const prefsSkippedVersion = 'app_update_skipped_version';

  static const androidAssetHint = 'android';
  static const windowsAssetHint = 'windows';
}
