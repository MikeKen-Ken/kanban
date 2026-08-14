import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/shared_content/shared_content.dart';
import 'package:kanban/features/wallpapers/wallpaper_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:kanban/webdav_sync/webdav_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('新建项目默认使用壁纸库随机轮播', () async {
    final tempDir = await Directory.systemTemp.createTemp('kanban_new_project_wp_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = BoardStorage(baseDirectory: tempDir, prefs: prefs);
    final repository = BoardRepository(prefs, storage);
    await repository.ensureInitialized();
    await storage.saveSharedContent(
      const SharedContent(
        wallpapers: [
          WallpaperAsset(id: 'w1', fileName: 'a.jpg'),
          WallpaperAsset(id: 'w2', fileName: 'b.jpg'),
        ],
        revision: 1,
        updatedAt: 1,
      ),
    );

    final projectId = await repository.createProject('新项目');
    final settings = await repository.loadProjectSettings(projectId);

    expect(settings.wallpaperIds, ['w1', 'w2']);
    expect(settings.wallpaperPlaybackMode, WallpaperPlaybackMode.random);
    expect(settings.wallpaperIntervalSeconds, 10);
  });
}
