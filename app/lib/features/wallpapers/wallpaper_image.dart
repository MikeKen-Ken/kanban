import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';

/// 只读取已持久化到本地的壁纸缓存，不在渲染期间发起网络请求。
class WallpaperImage extends StatefulWidget {
  const WallpaperImage({
    super.key,
    required this.wallpaperId,
    this.thumb = true,
    this.fit = BoxFit.cover,
  });

  final String wallpaperId;
  final bool thumb;
  final BoxFit fit;

  @override
  State<WallpaperImage> createState() => _WallpaperImageState();
}

class _WallpaperImageState extends State<WallpaperImage> {
  Future<Uint8List?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _read();
  }

  @override
  void didUpdateWidget(covariant WallpaperImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallpaperId != widget.wallpaperId ||
        oldWidget.thumb != widget.thumb) {
      _future = _read();
    }
  }

  Future<Uint8List?> _read() => context
      .read<BoardController>()
      .readWallpaperBytes(widget.wallpaperId, thumb: widget.thumb);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child:
                const Center(child: Icon(Icons.image_not_supported_outlined)),
          );
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          gaplessPlayback: true,
          width: double.infinity,
          height: double.infinity,
        );
      },
    );
  }
}
