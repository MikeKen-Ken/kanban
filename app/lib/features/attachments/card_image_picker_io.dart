import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';

import 'card_image_add_source.dart';
import 'card_image_picker_stub.dart';

Future<List<PickedImageBytes>> pickImagesForSource(
  CardImageAddSource source,
) {
  return switch (source) {
    CardImageAddSource.gallery => pickCardImagesFromGallery(),
    CardImageAddSource.camera => pickCardImageFromCamera(),
    CardImageAddSource.clipboard => pasteCardImagesFromClipboard(),
  };
}

Future<List<PickedImageBytes>> pickCardImagesFromGallery() async {
  if (Platform.isAndroid) {
    final imagePicker = ImagePicker();
    final files = await imagePicker.pickMultiImage();
    if (files.isEmpty) return const [];

    final results = <PickedImageBytes>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final name = file.name.isNotEmpty ? file.name : 'image.jpg';
      results.add(PickedImageBytes(bytes: bytes, fileName: name));
    }
    return results;
  }

  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: true,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return const [];

  final results = <PickedImageBytes>[];
  for (final file in result.files) {
    final bytes = file.bytes;
    if (bytes == null) continue;
    results.add(
      PickedImageBytes(
        bytes: bytes,
        fileName: file.name.isNotEmpty ? file.name : 'image.jpg',
      ),
    );
  }
  return results;
}

Future<List<PickedImageBytes>> pickCardImageFromCamera() async {
  if (!Platform.isAndroid) return const [];

  final imagePicker = ImagePicker();
  final file = await imagePicker.pickImage(source: ImageSource.camera);
  if (file == null) return const [];

  final bytes = await file.readAsBytes();
  final name = file.name.isNotEmpty ? file.name : 'camera.jpg';
  return [PickedImageBytes(bytes: bytes, fileName: name)];
}

Future<List<PickedImageBytes>> pasteCardImagesFromClipboard() async {
  if (!Platform.isWindows) return const [];

  final bytes = await Pasteboard.image;
  if (bytes == null || bytes.isEmpty) return const [];

  return [
    PickedImageBytes(
      bytes: Uint8List.fromList(bytes),
      fileName: 'clipboard.jpg',
    ),
  ];
}

/// 兼容旧调用：默认走相册/文件选择
Future<List<PickedImageBytes>> pickCardImages() =>
    pickCardImagesFromGallery();
