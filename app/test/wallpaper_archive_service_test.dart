import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/wallpapers/wallpaper_archive_service.dart';
import 'package:kanban/features/wallpapers/wallpaper_models.dart';

void main() {
  const service = WallpaperArchiveService();

  test('壁纸压缩包可往返清单与图片', () {
    const asset = WallpaperAsset(
      id: 'w1',
      fileName: '海.jpg',
      width: 10,
      height: 8,
      createdAt: 1,
      updatedAt: 2,
    );
    final encoded = service.encode(
      WallpaperArchivePackage(
        assets: const [asset],
        files: {
          WallpaperArchiveService.originalPath('w1'):
              Uint8List.fromList([1, 2, 3]),
          WallpaperArchiveService.thumbPath('w1'): Uint8List.fromList([9]),
        },
      ),
      createdAt: DateTime(2026, 8, 14),
    );

    final decoded = service.decode(encoded);
    expect(decoded.assets.single.id, 'w1');
    expect(decoded.assets.single.fileName, '海.jpg');
    expect(
      decoded.files[WallpaperArchiveService.originalPath('w1')],
      [1, 2, 3],
    );
  });

  test('拒绝目录穿越路径', () {
    expect(
      () => service.encode(
        WallpaperArchivePackage(
          assets: const [],
          files: {
            'wallpapers/../secret': Uint8List.fromList([1]),
          },
        ),
      ),
      throwsFormatException,
    );
  });
}
