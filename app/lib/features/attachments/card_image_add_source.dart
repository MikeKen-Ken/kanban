import 'package:flutter/material.dart';

enum CardImageAddSource {
  gallery,
  camera,
  clipboard,
}

extension CardImageAddSourceLabel on CardImageAddSource {
  String get label => switch (this) {
        CardImageAddSource.gallery => '从相册选择',
        CardImageAddSource.camera => '拍照',
        CardImageAddSource.clipboard => '粘贴图片',
      };

  IconData get icon => switch (this) {
        CardImageAddSource.gallery => Icons.photo_library_outlined,
        CardImageAddSource.camera => Icons.photo_camera_outlined,
        CardImageAddSource.clipboard => Icons.content_paste_go_outlined,
      };
}
