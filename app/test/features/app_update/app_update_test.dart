import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/app_update/github_release_client.dart';
import 'package:kanban/features/app_update/github_release_models.dart';
import 'package:kanban/features/app_update/version_compare.dart';

void main() {
  group('VersionCompare', () {
    test('解析 v 前缀与 build 号', () {
      expect(VersionCompare.parse('v1.2.3'), [1, 2, 3]);
      expect(VersionCompare.parse('1.2.3+10'), [1, 2, 3]);
      expect(VersionCompare.parse('2.0.0-beta'), [2, 0, 0]);
    });

    test('比较新旧版本', () {
      expect(VersionCompare.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(VersionCompare.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(VersionCompare.isNewer('0.9.9', '1.0.0'), isFalse);
      expect(VersionCompare.compare('v2.0.0', '1.9.9'), greaterThan(0));
    });
  });

  group('pickAssetForPlatform', () {
    final assets = [
      const GithubReleaseAsset(
        name: 'Kanban-1.0.0-android-arm64v8.apk',
        browserDownloadUrl: 'https://example.com/a.apk',
        size: 1,
        updatedAt: null,
      ),
      const GithubReleaseAsset(
        name: 'Kanban-1.0.0-windows-x86-64.zip',
        browserDownloadUrl: 'https://example.com/w.zip',
        size: 2,
        updatedAt: null,
      ),
    ];

    test('Android 选 apk', () {
      final picked = pickAssetForPlatform(
        assets,
        android: true,
        windows: false,
      );
      expect(picked?.name, contains('android'));
    });

    test('Windows 选 zip', () {
      final picked = pickAssetForPlatform(
        assets,
        android: false,
        windows: true,
      );
      expect(picked?.name, contains('windows'));
    });
  });

  group('GithubReleaseInfo.fromJson', () {
    test('解析 release JSON', () {
      final info = GithubReleaseInfo.fromJson({
        'tag_name': 'v1.2.0',
        'name': '1.2.0',
        'body': '修复',
        'html_url': 'https://github.com/x/y/releases/tag/v1.2.0',
        'draft': false,
        'prerelease': false,
        'published_at': '2026-08-05T00:00:00Z',
        'assets': [
          {
            'name': 'app.apk',
            'browser_download_url': 'https://example.com/app.apk',
            'size': 10,
            'updated_at': '2026-08-05T01:00:00Z',
          },
        ],
      });
      expect(info.versionLabel, '1.2.0');
      expect(info.assets, hasLength(1));
      expect(info.assets.first.name, 'app.apk');
    });
  });
}
