import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/webdav_sync/webdav_config.dart';

void main() {
  test('poll interval clamps to 60–600 and defaults to 600', () {
    expect(WebDavConfig.minPollIntervalSeconds, 60);
    expect(WebDavConfig.maxPollIntervalSeconds, 600);
    expect(WebDavConfig.defaultPollIntervalSeconds, 600);

    expect(WebDavConfig.clampPollIntervalSeconds(15), 60);
    expect(WebDavConfig.clampPollIntervalSeconds(30), 60);
    expect(WebDavConfig.clampPollIntervalSeconds(120), 120);
    expect(WebDavConfig.clampPollIntervalSeconds(900), 600);
  });

  test('push debounce clamps to 5–60 and defaults to 60', () {
    expect(WebDavConfig.minPushDebounceSeconds, 5);
    expect(WebDavConfig.maxPushDebounceSeconds, 60);
    expect(WebDavConfig.defaultPushDebounceSeconds, 60);

    expect(WebDavConfig.clampPushDebounceSeconds(1), 5);
    expect(WebDavConfig.clampPushDebounceSeconds(10), 10);
    expect(WebDavConfig.clampPushDebounceSeconds(120), 60);
  });

  test('fromJson upgrades legacy short intervals and fills debounce default', () {
    final config = WebDavConfig.fromJson({
      'enabled': true,
      'serverUrl': 'https://example.com/dav',
      'username': 'u',
      'password': 'p',
      'remotePath': '/KanbanApp',
      'autoSync': true,
      'pollIntervalSeconds': 15,
    });
    expect(config.pollIntervalSeconds, 60);
    expect(config.pushDebounceSeconds, 60);
    expect(config.autoSync, isFalse);
    expect(config.autoPull, isFalse);
  });

  test('fromJson 忽略已保存的自动上传/拉取开关', () {
    final withPull = WebDavConfig.fromJson({
      'enabled': true,
      'serverUrl': 'https://example.com/dav',
      'username': 'u',
      'password': 'p',
      'autoSync': true,
      'autoPull': true,
    });
    expect(withPull.autoSync, isFalse);
    expect(withPull.autoPull, isFalse);

    final legacy = WebDavConfig.fromJson({
      'enabled': true,
      'serverUrl': 'https://example.com/dav',
      'username': 'u',
      'password': 'p',
      'autoSync': false,
    });
    expect(legacy.autoSync, isFalse);
    expect(legacy.autoPull, isFalse);
  });
}
