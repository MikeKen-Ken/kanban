import 'dart:typed_data';

/// 从文件选择器读取的单个文件。
class PickedFileBytes {
  const PickedFileBytes({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

const maxCardFileBytes = 10 * 1024 * 1024;
