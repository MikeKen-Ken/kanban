import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/app_update/app_update_installer.dart';
import 'package:kanban/features/app_update/github_release_client.dart';
import 'package:kanban/features/app_update/github_release_models.dart';
import 'package:kanban/features/app_update/release_notes_plain_text.dart';
import 'package:kanban/features/app_update/version_compare.dart';
import 'package:path/path.dart' as p;

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

  group('releaseNotesToPlainText', () {
    test('将 Atom HTML 说明转为可读纯文本', () {
      const html = '''
<h2>更新内容</h2>
<p>相对 v1.0.0 的提交：</p>
<ul>
<li>功能：新增软件内更新。 (<a class="commit-link" href="https://github.com/MikeKen-Ken/kanban/commit/40e7ff9"><tt>40e7ff9</tt></a>)</li>
<li>配置：Release 更新说明改为列出相对上一版本的提交。 (<a href="https://github.com/x/y/commit/eebf800"><tt>eebf800</tt></a>)</li>
</ul>
<p>完整对比：<a href="https://github.com/MikeKen-Ken/kanban/compare/v1.0.0...v1.0.1"><tt>v1.0.0...v1.0.1</tt></a></p>
''';
      final plain = releaseNotesToPlainText(html);
      expect(plain, isNot(contains('<')));
      expect(plain, contains('更新内容'));
      expect(plain, contains('- 功能：新增软件内更新。 (40e7ff9)'));
      expect(plain, contains('完整对比：v1.0.0...v1.0.1'));
    });

    test('Markdown 标题标记会被去掉', () {
      const md = '''
## 更新内容

相对 v1.0.0 的提交：

- 功能：新增更新 (40e7ff9)
''';
      final plain = releaseNotesToPlainText(md);
      expect(plain, startsWith('更新内容'));
      expect(plain, contains('- 功能：新增更新 (40e7ff9)'));
      expect(plain, isNot(contains('##')));
    });
  });

  group('parseReleasesAtom', () {
    test('解析最新 entry 的 tag 与标题，并去掉 HTML 标签', () {
      const atom = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>tag:github.com,2008:Repository/1/v1.0.1</id>
    <updated>2026-08-04T23:07:50Z</updated>
    <link rel="alternate" type="text/html" href="https://github.com/MikeKen-Ken/kanban/releases/tag/v1.0.1"/>
    <title>1.0.1</title>
    <content type="html">&lt;h2&gt;更新内容&lt;/h2&gt;
&lt;p&gt;相对 v1.0.0 的提交：&lt;/p&gt;
&lt;ul&gt;
&lt;li&gt;功能：新增更新 (&lt;a href=&quot;https://example.com/c&quot;&gt;&lt;tt&gt;40e7ff9&lt;/tt&gt;&lt;/a&gt;)&lt;/li&gt;
&lt;/ul&gt;</content>
  </entry>
</feed>
''';
      final list = parseReleasesAtom(
        atom,
        owner: 'MikeKen-Ken',
        repo: 'kanban',
      );
      expect(list, hasLength(1));
      expect(list.first.tagName, 'v1.0.1');
      expect(list.first.versionLabel, '1.0.1');
      expect(list.first.body, isNot(contains('<')));
      expect(list.first.body, contains('更新内容'));
      expect(list.first.body, contains('- 功能：新增更新 (40e7ff9)'));
    });
  });

  group('parseJsdelivrGhPackage', () {
    test('将 versions 转为带 v 前缀的 tag', () {
      const json = '''
{"type":"gh","name":"MikeKen-Ken/kanban","versions":[
  {"version":"1.0.1"},
  {"version":"1.0.0"}
]}
''';
      final list = parseJsdelivrGhPackage(
        json,
        owner: 'MikeKen-Ken',
        repo: 'kanban',
      );
      expect(list.map((r) => r.tagName).toList(), ['v1.0.1', 'v1.0.0']);
      expect(list.first.versionLabel, '1.0.1');
    });
  });

  group('GithubReleaseClient.fetchReleases', () {
    test('Atom 失败且 API 403 时仍可通过 jsDelivr 获取版本', () async {
      final client = GithubReleaseClient(
        httpGet: (uri) async {
          if (uri.host == 'github.com') {
            return const ReleaseHttpResult(
                statusCode: 503, body: 'unavailable');
          }
          if (uri.host == 'api.github.com') {
            return const ReleaseHttpResult(
              statusCode: 403,
              body: '{"message":"API rate limit exceeded"}',
              rateLimitRemaining: '0',
            );
          }
          if (uri.host == 'data.jsdelivr.com') {
            return const ReleaseHttpResult(
              statusCode: 200,
              body:
                  '{"type":"gh","versions":[{"version":"1.0.1"},{"version":"1.0.0"}]}',
            );
          }
          fail('未预期的请求：${uri.host}');
        },
      );
      try {
        final list = await client.fetchReleases();
        expect(list.first.tagName, 'v1.0.1');
        expect(list, hasLength(2));
      } finally {
        client.close();
      }
    });

    test('全部来源失败时错误信息包含 API 403 限额提示', () async {
      final client = GithubReleaseClient(
        httpGet: (uri) async {
          if (uri.host == 'github.com') {
            return const ReleaseHttpResult(statusCode: 503, body: '');
          }
          if (uri.host == 'data.jsdelivr.com') {
            return const ReleaseHttpResult(statusCode: 500, body: '');
          }
          return const ReleaseHttpResult(
            statusCode: 403,
            body: '{"message":"API rate limit exceeded"}',
            rateLimitRemaining: '0',
          );
        },
      );
      try {
        await expectLater(
          client.fetchReleases(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Atom'),
                contains('jsDelivr'),
                contains('403'),
                contains('限额'),
              ),
            ),
          ),
        );
      } finally {
        client.close();
      }
    });
  });

  group('windowsUpdaterScript', () {
    test('脚本主体保持 ASCII，避免 PS 5.1 解析中文失败', () {
      final nonAscii = windowsUpdaterScript.runes
          .where((r) => r > 0x7F)
          .toList(growable: false);
      expect(
        nonAscii,
        isEmpty,
        reason: 'updater .ps1 含非 ASCII 时，Windows PowerShell 5.1 可能 ParserError',
      );
    });

    test('先复制应用文件，agent_worker 失败时仍启动可见窗口', () {
      expect(windowsUpdaterScript, contains('Copy app files'));
      expect(windowsUpdaterScript, contains('Copy agent worker'));
      expect(windowsUpdaterScript, contains(r"'\agent_worker\'"));
      expect(
        windowsUpdaterScript,
        contains(
          r'Start-Process -FilePath $ExePath -WorkingDirectory $InstallDir -WindowStyle Normal',
        ),
      );
    });

    test('UTF-8 无 BOM 写入后仍能覆盖安装目录并成功退出', () async {
      if (!Platform.isWindows) {
        return;
      }

      final temp = Directory.systemTemp.path;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final installDir = Directory(p.join(temp, 'kanban_upd_install_$stamp'));
      final sourceDir = Directory(p.join(temp, 'kanban_upd_source_$stamp'));
      final scriptFile = File(p.join(temp, 'kanban_upd_script_$stamp.ps1'));
      final logFile = File(p.join(temp, 'kanban_updater_1.log'));

      await installDir.create(recursive: true);
      await sourceDir.create(recursive: true);
      await Directory(p.join(sourceDir.path, 'data')).create();

      final oldExe = File(p.join(installDir.path, 'kanban.exe'));
      final newExe = File(p.join(sourceDir.path, 'kanban.exe'));
      await oldExe.writeAsString('OLD');
      await newExe.writeAsString('NEW');
      await File(p.join(sourceDir.path, 'data', 'app.so')).writeAsString('so');
      // 模拟 Dart writeAsString 默认：UTF-8 无 BOM
      await scriptFile.writeAsString(windowsUpdaterScript, flush: true);

      try {
        final result = await Process.run(
          'powershell.exe',
          [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            scriptFile.path,
            '-InstallDir',
            installDir.path,
            '-SourceDir',
            sourceDir.path,
            '-ExePath',
            oldExe.path,
            '-TargetPid',
            '1',
            '-SkipLaunch',
          ],
        );
        expect(
          result.exitCode,
          0,
          reason: 'stdout=${result.stdout}\nstderr=${result.stderr}\n'
              'log=${await logFile.readAsString()}',
        );

        expect(await oldExe.readAsString(), 'NEW');
        expect(
          await File(p.join(installDir.path, 'data', 'app.so')).readAsString(),
          'so',
        );

        final topNames = installDir
            .listSync()
            .map((e) => p.basename(e.path).toLowerCase())
            .toSet();
        expect(topNames, equals({'kanban.exe', 'data'}));
      } finally {
        if (await installDir.exists()) {
          await installDir.delete(recursive: true);
        }
        if (await sourceDir.exists()) {
          await sourceDir.delete(recursive: true);
        }
        if (await scriptFile.exists()) {
          await scriptFile.delete();
        }
        if (await logFile.exists()) {
          await logFile.delete();
        }
      }
    });

    test('TEMP 为 8.3 短路径时仍覆盖安装目录根文件', () async {
      if (!Platform.isWindows) {
        return;
      }

      final temp = Directory.systemTemp.path;
      // 本机常见：TEMP 已是 ADMINI~1 形式；若无波浪号则无法复现该 bug，直接跳过。
      if (!temp.contains('~')) {
        return;
      }

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final installDir = Directory(p.join(temp, 'kanban_upd_install_$stamp'));
      final sourceDir = Directory(p.join(temp, 'kanban_upd_source_$stamp'));
      final scriptFile = File(p.join(temp, 'kanban_upd_script_$stamp.ps1'));
      final logFile = File(p.join(temp, 'kanban_updater_1.log'));

      await installDir.create(recursive: true);
      await sourceDir.create(recursive: true);
      await Directory(p.join(sourceDir.path, 'data')).create();

      final oldExe = File(p.join(installDir.path, 'kanban.exe'));
      final newExe = File(p.join(sourceDir.path, 'kanban.exe'));
      await oldExe.writeAsString('OLD');
      await newExe.writeAsString('NEW');
      await File(p.join(sourceDir.path, 'data', 'app.so')).writeAsString('so');
      await scriptFile.writeAsString(windowsUpdaterScript);

      try {
        final result = await Process.run(
          'powershell.exe',
          [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            scriptFile.path,
            '-InstallDir',
            installDir.path,
            '-SourceDir',
            sourceDir.path,
            '-ExePath',
            oldExe.path,
            '-TargetPid',
            '1',
            '-SkipLaunch',
          ],
        );
        expect(
          result.exitCode,
          0,
          reason: 'stdout=${result.stdout}\nstderr=${result.stderr}\n'
              'log=${await logFile.readAsString()}',
        );

        expect(await oldExe.readAsString(), 'NEW');
        expect(
          await File(p.join(installDir.path, 'data', 'app.so')).readAsString(),
          'so',
        );
        // 只应覆盖到安装根目录，不应因相对路径算错多出一层无关目录
        final topNames = installDir
            .listSync()
            .map((e) => p.basename(e.path).toLowerCase())
            .toSet();
        expect(topNames, equals({'kanban.exe', 'data'}));
      } finally {
        if (await installDir.exists()) {
          await installDir.delete(recursive: true);
        }
        if (await sourceDir.exists()) {
          await sourceDir.delete(recursive: true);
        }
        if (await scriptFile.exists()) {
          await scriptFile.delete();
        }
        if (await logFile.exists()) {
          await logFile.delete();
        }
      }
    });
  });

  group('resolveWindowsPayloadRoot', () {
    test('单层嵌套目录时定位到含 exe 的根', () async {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final root = Directory(
        p.join(Directory.systemTemp.path, 'kanban_payload_$stamp'),
      );
      final nested = Directory(p.join(root.path, 'Release'));
      await nested.create(recursive: true);
      await File(p.join(nested.path, 'kanban.exe')).writeAsString('x');

      try {
        final resolved = await AppUpdateInstaller.resolveWindowsPayloadRoot(
          root,
          exeFileName: 'kanban.exe',
        );
        expect(p.normalize(resolved.path), p.normalize(nested.path));
      } finally {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      }
    });
  });
}
