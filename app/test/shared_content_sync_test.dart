import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/activity/activity_models.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/features/shared_content/shared_content.dart';
import 'package:kanban/features/sync_conflict/sync_conflict.dart';
import 'package:kanban/features/templates/card_template.dart';
import 'package:kanban/features/views/filter_spec.dart';
import 'package:kanban/features/views/saved_view.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:kanban/storage/board_storage_web.dart';
import 'package:shared_preferences/shared_preferences.dart';

SharedContent _content({
  List<SharedLabel> labels = const [],
  List<SavedView> views = const [],
  List<CardTemplate> templates = const [],
  Map<String, ActivityLog> activity = const {},
  int revision = 1,
  int updatedAt = 1,
}) {
  return SharedContent(
    labels: labels,
    savedViews: views,
    cardTemplates: templates,
    activityByProject: activity,
    revision: revision,
    updatedAt: updatedAt,
  );
}

ActivityEvent _event(String id, int occurredAt) {
  return ActivityEvent(
    id: id,
    projectId: 'p1',
    entityType: 'card',
    entityId: 'c1',
    entityTitle: '卡片',
    action: ActivityAction.updated,
    occurredAt: occurredAt,
  );
}

void main() {
  test('共享内容 JSON 往返保留标签、视图、模板和活动历史', () {
    final original = _content(
      labels: const [
        SharedLabel(id: 'l1', name: '重要', colorValue: 0xFFFF0000, updatedAt: 2),
      ],
      views: const [
        SavedView(
          id: 'v1',
          name: '今日重要',
          filter: FilterSpec(labelIds: ['l1']),
          updatedAt: 3,
        ),
      ],
      templates: const [
        CardTemplate(
          id: 't1',
          name: '周报',
          title: '填写周报',
          updatedAt: 4,
        ),
      ],
      activity: {
        'p1': ActivityLog(events: [_event('e1', 5)]),
      },
      revision: 5,
      updatedAt: 6,
    );

    final restored = SharedContent.fromJson(original.toJson());

    expect(restored.labels.single.id, 'l1');
    expect(restored.savedViews.single.filter.labelIds, ['l1']);
    expect(restored.cardTemplates.single.title, '填写周报');
    expect(restored.activityByProject['p1']?.events.single.id, 'e1');
    expect(restored.revision, 5);
  });

  test('旧工作区 JSON 缺共享字段时使用未初始化安全默认值', () {
    final snapshot = ProjectWorkspaceSnapshot.fromJson({
      'manifest': const ProjectsManifest(
        projects: [],
        updatedAt: 0,
        revision: 0,
      ).toJson(),
      'boards': <String, dynamic>{},
      'settings': <String, dynamic>{},
    });

    expect(snapshot.sharedContent.isUninitialized, isTrue);
    expect(snapshot.sharedContent.labels, isEmpty);
  });

  test('旧端缺共享文件不会删除新端内容', () {
    final local = _content(
      labels: const [
        SharedLabel(id: 'l1', name: '本地标签', colorValue: 1, updatedAt: 10),
      ],
    );

    final merged = mergeSharedContent(
      local: local,
      remote: SharedContent.empty,
      base: local,
    );

    expect(merged.labels.single.name, '本地标签');
  });

  test('标签、视图和模板按 id 三路合并', () {
    final base = _content(
      labels: const [
        SharedLabel(id: 'l1', name: '原标签', colorValue: 1, updatedAt: 1),
      ],
      views: const [
        SavedView(id: 'v1', name: '原视图', filter: FilterSpec(), updatedAt: 1),
      ],
      templates: const [
        CardTemplate(id: 't1', name: '原模板', title: '原题', updatedAt: 1),
      ],
    );
    final local = _content(
      labels: const [
        SharedLabel(id: 'l1', name: '本地标签', colorValue: 1, updatedAt: 20),
      ],
      views: base.savedViews,
      templates: base.cardTemplates,
      revision: 2,
      updatedAt: 20,
    );
    final remote = _content(
      labels: base.labels,
      views: const [
        SavedView(id: 'v1', name: '远端视图', filter: FilterSpec(), updatedAt: 30),
      ],
      templates: const [
        CardTemplate(id: 't1', name: '远端模板', title: '新题', updatedAt: 40),
      ],
      revision: 3,
      updatedAt: 40,
    );

    final merged = mergeSharedContent(local: local, remote: remote, base: base);

    expect(merged.labels.single.name, '本地标签');
    expect(merged.savedViews.single.name, '远端视图');
    expect(merged.cardTemplates.single.title, '新题');
  });

  test('活动事件按 id 并集并限制长度', () {
    final localEvents = [
      for (var i = 0; i < 700; i++) _event('local-$i', i),
    ];
    final remoteEvents = [
      for (var i = 0; i < 700; i++) _event('remote-$i', 1000 + i),
      _event('local-0', 0),
    ];

    final merged = mergeSharedContent(
      local: _content(activity: {'p1': ActivityLog(events: localEvents)}),
      remote: _content(activity: {'p1': ActivityLog(events: remoteEvents)}),
    );
    final events = merged.activityByProject['p1']!.events;

    expect(events, hasLength(ActivityLog.maxEvents));
    expect(events.map((event) => event.id).toSet(), hasLength(events.length));
    expect(events.first.id, 'remote-699');
  });

  test('IO 存储缺文件返回默认值并可完成 JSON 往返', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final base =
        await Directory.systemTemp.createTemp('kanban_shared_content_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });
    final storage = BoardStorage(baseDirectory: base, prefs: prefs);

    expect((await storage.loadSharedContent()).isUninitialized, isTrue);

    final content = _content(
      labels: const [
        SharedLabel(id: 'l1', name: '同步标签', colorValue: 7, updatedAt: 8),
      ],
      revision: 2,
      updatedAt: 8,
    );
    await storage.saveSharedContent(content);

    final restored = await storage.loadSharedContent();
    expect(restored.labels.single.name, '同步标签');
    expect(restored.revision, 2);
  });

  test('Web 存储缺键返回默认值并可完成 JSON 往返', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = BoardStorageWeb(prefs);

    expect((await storage.loadSharedContent()).isUninitialized, isTrue);

    final content = _content(
      views: const [
        SavedView(
          id: 'v1',
          name: 'Web 视图',
          filter: FilterSpec(keyword: '待办'),
          updatedAt: 9,
        ),
      ],
      revision: 3,
      updatedAt: 9,
    );
    await storage.saveSharedContent(content);

    final restored = await storage.loadSharedContent();
    expect(restored.savedViews.single.name, 'Web 视图');
    expect(restored.revision, 3);
  });
}
