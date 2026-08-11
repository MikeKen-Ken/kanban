import 'dart:typed_data';

import '../../models/kanban_models.dart';
import '../wallpapers/wallpaper_models.dart';

/// 卡片附件存储抽象（Android / Windows 有 IO 实现）
abstract class AttachmentStore {
  Future<CardAttachment> saveImage({
    required String projectId,
    required Uint8List sourceBytes,
    required String fileName,
    required int order,
    int? createdAt,
  });

  Future<void> writeBytes({
    required String projectId,
    required String attachmentId,
    required Uint8List bytes,
    bool thumb = false,
  });

  Future<Uint8List?> readBytes({
    required String projectId,
    required String attachmentId,
    bool thumb = false,
  });

  Future<bool> exists({
    required String projectId,
    required String attachmentId,
    bool thumb = false,
  });

  Future<void> deleteAttachment({
    required String projectId,
    required String attachmentId,
  });

  Future<void> deleteAttachments({
    required String projectId,
    required Iterable<CardAttachment> attachments,
  });

  Future<Set<String>> listLocalAttachmentIds(String projectId);

  Future<void> deleteOrphans({
    required String projectId,
    required Set<String> keepIds,
  });

  Future<WallpaperAsset> saveWallpaper({
    required Uint8List sourceBytes,
    required String fileName,
    int? createdAt,
  });

  Future<void> writeWallpaperBytes({
    required String wallpaperId,
    required Uint8List bytes,
    bool thumb = false,
  });

  Future<Uint8List?> readWallpaperBytes(
    String wallpaperId, {
    bool thumb = false,
  });

  Future<bool> wallpaperExists(String wallpaperId, {bool thumb = false});

  Future<void> deleteWallpaper(String wallpaperId);

  Future<Set<String>> listLocalWallpaperIds();

  Future<void> deleteOrphanWallpapers(Set<String> keepIds);
}
