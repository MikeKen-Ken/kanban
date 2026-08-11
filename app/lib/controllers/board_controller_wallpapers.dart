part of 'board_controller.dart';

extension BoardControllerWallpapers on BoardController {
  List<WallpaperAsset> get wallpapers => sharedContent.wallpapers;

  Future<Uint8List?> readWallpaperBytes(
    String wallpaperId, {
    bool thumb = true,
  }) async =>
      attachmentStore?.readWallpaperBytes(wallpaperId, thumb: thumb);

  /// 多选上传到工作区壁纸库；图片处理后立即写入本地缓存。
  Future<String?> uploadWallpapersFromGallery() async {
    return _withBoardMutation(() async {
      final store = attachmentStore;
      if (store == null) return '当前平台不支持壁纸图片';
      final picked = await pickCardImagesFromGallery();
      if (picked.isEmpty) return null;

      final added = <WallpaperAsset>[];
      try {
        for (final image in picked) {
          added.add(
            await store.saveWallpaper(
              sourceBytes: image.bytes,
              fileName: image.fileName,
            ),
          );
        }
      } catch (_) {
        for (final asset in added) {
          await store.deleteWallpaper(asset.id);
        }
        return '图片处理失败';
      }

      await _persistSharedContent(
        sharedContent
            .copyWith(wallpapers: [...sharedContent.wallpapers, ...added]),
      );
      return null;
    });
  }

  Future<void> setProjectWallpapers({
    required List<String> wallpaperIds,
    required WallpaperPlaybackMode mode,
    required int intervalSeconds,
  }) async {
    return _withBoardMutation(() async {
      final available = sharedContent.wallpapers.map((item) => item.id).toSet();
      var selected = wallpaperIds
          .where(available.contains)
          .toSet()
          .toList(growable: false);
      if (mode == WallpaperPlaybackMode.fixed && selected.length > 1) {
        selected = [selected.first];
      }
      await _persistProjectSettings(
        projectSettings
            .copyWith(
              backgroundAttachmentId: selected.isEmpty ? '' : selected.first,
              wallpaperIds: selected,
              wallpaperPlaybackMode:
                  selected.length > 1 ? mode : WallpaperPlaybackMode.fixed,
              wallpaperIntervalSeconds: intervalSeconds,
              clearConflictSide: true,
            )
            .bump(),
      );
    });
  }

  Future<void> deleteWallpapers(Set<String> wallpaperIds) async {
    if (wallpaperIds.isEmpty) return;
    return _withBoardMutation(() async {
      final existing = sharedContent.wallpapers
          .where((item) => wallpaperIds.contains(item.id))
          .toList(growable: false);
      if (existing.isEmpty) return;

      await _persistSharedContent(
        sharedContent.copyWith(
          wallpapers: sharedContent.wallpapers
              .where((item) => !wallpaperIds.contains(item.id))
              .toList(growable: false),
        ),
      );

      for (final entry in manifest?.projects ?? const <ProjectEntry>[]) {
        final current = entry.id == activeProjectId
            ? projectSettings
            : await _repository.loadProjectSettings(entry.id);
        final selected = current.wallpaperIds
            .where((id) => !wallpaperIds.contains(id))
            .toList(growable: false);
        final legacyRemoved =
            wallpaperIds.contains(current.backgroundAttachmentId);
        if (selected.length == current.wallpaperIds.length && !legacyRemoved) {
          continue;
        }
        final next = current
            .copyWith(
              wallpaperIds: selected,
              backgroundAttachmentId: legacyRemoved
                  ? (selected.isEmpty ? '' : selected.first)
                  : current.backgroundAttachmentId,
              wallpaperPlaybackMode: selected.length > 1
                  ? current.wallpaperPlaybackMode
                  : WallpaperPlaybackMode.fixed,
              clearConflictSide: true,
            )
            .bump();
        await _repository.saveProjectSettings(entry.id, next);
        if (entry.id == activeProjectId) projectSettings = next;
      }

      final store = attachmentStore;
      if (store != null) {
        for (final asset in existing) {
          await store.deleteWallpaper(asset.id);
        }
      }
      notifyListeners();
      _markWorkspaceChanged();
    });
  }
}
