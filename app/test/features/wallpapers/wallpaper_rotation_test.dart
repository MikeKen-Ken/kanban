import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/project/project_settings.dart';
import 'package:kanban/features/wallpapers/wallpaper_models.dart';

void main() {
  test('随机轮播候选来自壁纸库全集而非项目快照', () {
    const settings = ProjectSettings(
      wallpaperIds: ['w1'],
      wallpaperPlaybackMode: WallpaperPlaybackMode.random,
    );

    expect(
      settings.wallpaperRotationCandidateIds(['w1', 'w2', 'w3']),
      ['w1', 'w2', 'w3'],
    );
  });

  test('固定模式仍使用项目选择的壁纸', () {
    const settings = ProjectSettings(
      wallpaperIds: ['w1'],
      wallpaperPlaybackMode: WallpaperPlaybackMode.fixed,
    );

    expect(
      settings.wallpaperRotationCandidateIds(['w1', 'w2', 'w3']),
      ['w1'],
    );
  });

  test('随机轮播在壁纸库为空时回退到项目有效壁纸', () {
    const settings = ProjectSettings(
      wallpaperIds: ['legacy-a'],
      wallpaperPlaybackMode: WallpaperPlaybackMode.random,
    );

    expect(
      settings.wallpaperRotationCandidateIds(const []),
      ['legacy-a'],
    );
  });
}
