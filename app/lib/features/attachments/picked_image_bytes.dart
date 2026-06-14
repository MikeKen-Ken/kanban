import 'dart:typed_data';

/// 从相册、相机或剪贴板选取的图片字节与文件名
class PickedImageBytes {
  const PickedImageBytes({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}
