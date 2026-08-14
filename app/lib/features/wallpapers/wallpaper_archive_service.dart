import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../../storage/kanban_paths.dart';
import 'wallpaper_models.dart';

/// 壁纸库覆盖同步用的压缩包内容。
class WallpaperArchivePackage {
  const WallpaperArchivePackage({
    required this.assets,
    this.files = const {},
  });

  final List<WallpaperAsset> assets;

  /// 路径格式：`wallpapers/{id}.jpg` 与 `wallpapers/{id}_thumb.jpg`
  final Map<String, Uint8List> files;
}

class WallpaperArchiveService {
  const WallpaperArchiveService();

  static const formatVersion = 1;
  static const _manifestPath = 'wallpaper_manifest.json';
  static const _catalogPath = 'wallpapers.json';

  Uint8List encode(WallpaperArchivePackage package, {DateTime? createdAt}) {
    final archive = Archive();
    final checksums = <String, String>{};

    final catalogBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'items': package.assets.map((item) => item.toJson()).toList(),
        }),
      ),
    );
    archive.addFile(ArchiveFile.bytes(_catalogPath, catalogBytes));
    checksums[_catalogPath] = sha256.convert(catalogBytes).toString();

    for (final entry in package.files.entries) {
      final path = _safeFilePath(entry.key);
      archive.addFile(ArchiveFile.bytes(path, entry.value));
      checksums[path] = sha256.convert(entry.value).toString();
    }

    final manifestBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': formatVersion,
          'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
          'checksums': checksums,
        }),
      ),
    );
    archive.addFile(ArchiveFile.bytes(_manifestPath, manifestBytes));
    return ZipEncoder().encodeBytes(archive);
  }

  WallpaperArchivePackage decode(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, Uint8List>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final path = _safeArchivePath(file.name);
      final content = file.readBytes();
      if (content != null) files[path] = content;
    }

    final manifestBytes = files[_manifestPath];
    if (manifestBytes == null) {
      throw const FormatException('壁纸包缺少清单文件');
    }
    final manifest =
        jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    if (manifest['version'] != formatVersion) {
      throw FormatException('不支持的壁纸包版本：${manifest['version']}');
    }
    final checksumsRaw = manifest['checksums'];
    if (checksumsRaw is! Map) {
      throw const FormatException('壁纸包校验信息无效');
    }
    final declaredPaths = <String>{};
    for (final entry in checksumsRaw.entries) {
      final path = _safeArchivePath(entry.key.toString());
      declaredPaths.add(path);
      final content = files[path];
      if (content == null ||
          sha256.convert(content).toString() != entry.value.toString()) {
        throw FormatException('壁纸包文件校验失败：$path');
      }
    }
    final actualPaths =
        files.keys.where((path) => path != _manifestPath).toSet();
    if (actualPaths.length != declaredPaths.length ||
        !actualPaths.containsAll(declaredPaths)) {
      throw const FormatException('壁纸包包含未声明文件或校验清单不完整');
    }

    final catalogBytes = files[_catalogPath];
    if (catalogBytes == null) {
      throw const FormatException('壁纸包缺少目录');
    }
    final catalog =
        jsonDecode(utf8.decode(catalogBytes)) as Map<String, dynamic>;
    return WallpaperArchivePackage(
      assets: [
        for (final item in catalog['items'] as List<dynamic>? ?? const [])
          WallpaperAsset.fromJson(item as Map<String, dynamic>),
      ],
      files: {
        for (final entry in files.entries)
          if (entry.key.startsWith('wallpapers/')) entry.key: entry.value,
      },
    );
  }

  static String originalPath(String wallpaperId) =>
      'wallpapers/$wallpaperId.${KanbanPaths.attachmentFileExt}';

  static String thumbPath(String wallpaperId) =>
      'wallpapers/${wallpaperId}_thumb.${KanbanPaths.attachmentFileExt}';

  String _safeFilePath(String path) {
    final safe = _safeArchivePath(path.replaceAll('\\', '/'));
    if (!safe.startsWith('wallpapers/')) {
      throw const FormatException('壁纸文件必须位于 wallpapers 目录');
    }
    return safe;
  }

  String _safeArchivePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        normalized.split('/').any((segment) => segment == '..')) {
      throw FormatException('壁纸包包含不安全路径：$path');
    }
    return normalized;
  }
}
