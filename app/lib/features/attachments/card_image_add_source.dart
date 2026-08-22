import 'package:flutter/material.dart';

enum CardImageAddSource {
  gallery,
  camera,
  clipboard,
}

extension CardImageAddSourceLabel on CardImageAddSource {
  String get label => switch (this) {
        CardImageAddSource.gallery => 'Choose from gallery',
        CardImageAddSource.camera => 'Take photo',
        CardImageAddSource.clipboard => 'Paste image',
      };

  IconData get icon => switch (this) {
        CardImageAddSource.gallery => Icons.photo_library_outlined,
        CardImageAddSource.camera => Icons.photo_camera_outlined,
        CardImageAddSource.clipboard => Icons.content_paste_go_outlined,
      };
}
