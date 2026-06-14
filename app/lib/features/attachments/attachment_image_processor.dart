import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ProcessedImage {
  const ProcessedImage({
    required this.fullBytes,
    required this.thumbBytes,
    required this.width,
    required this.height,
  });

  final Uint8List fullBytes;
  final Uint8List thumbBytes;
  final int width;
  final int height;
}

/// 解码、缩放并压缩图片，输出 JPEG 原图与缩略图
ProcessedImage? processAttachmentImage(
  Uint8List source, {
  int maxDimension = 1920,
  int thumbMaxDimension = 400,
  int quality = 85,
}) {
  final decoded = img.decodeImage(source);
  if (decoded == null) return null;

  final resized = _resize(decoded, maxDimension);
  final thumb = _resize(decoded, thumbMaxDimension);
  final fullBytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  final thumbBytes = Uint8List.fromList(img.encodeJpg(thumb, quality: quality));

  return ProcessedImage(
    fullBytes: fullBytes,
    thumbBytes: thumbBytes,
    width: resized.width,
    height: resized.height,
  );
}

img.Image _resize(img.Image source, int maxDimension) {
  final longest = source.width > source.height ? source.width : source.height;
  if (longest <= maxDimension) return source;
  if (source.width >= source.height) {
    return img.copyResize(source, width: maxDimension);
  }
  return img.copyResize(source, height: maxDimension);
}
