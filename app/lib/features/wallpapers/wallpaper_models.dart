enum WallpaperPlaybackMode { fixed, random }

extension WallpaperPlaybackModeX on WallpaperPlaybackMode {
  static WallpaperPlaybackMode fromString(String? value) =>
      value == WallpaperPlaybackMode.random.name
          ? WallpaperPlaybackMode.random
          : WallpaperPlaybackMode.fixed;
}

/// 工作区级壁纸资源元数据；图片文件保存在本地/远端 wallpapers 目录。
class WallpaperAsset {
  const WallpaperAsset({
    required this.id,
    required this.fileName,
    this.width = 0,
    this.height = 0,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String id;
  final String fileName;
  final int width;
  final int height;
  final int createdAt;
  final int updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        if (width > 0) 'width': width,
        if (height > 0) 'height': height,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory WallpaperAsset.fromJson(Map<String, dynamic> json) {
    int readInt(Object? value) => value is num ? value.toInt() : 0;
    return WallpaperAsset(
      id: json['id'] as String? ?? '',
      fileName: json['fileName'] as String? ?? 'wallpaper.jpg',
      width: readInt(json['width']),
      height: readInt(json['height']),
      createdAt: readInt(json['createdAt']),
      updatedAt: readInt(json['updatedAt']),
    );
  }
}
