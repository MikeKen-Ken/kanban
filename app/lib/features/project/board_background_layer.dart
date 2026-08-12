import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../wallpapers/wallpaper_models.dart';
import 'project_settings.dart';

/// 看板全屏背景层。轮播只读取本地持久化缓存，不触发 WebDAV 请求。
class BoardBackgroundLayer extends StatefulWidget {
  const BoardBackgroundLayer({
    super.key,
    required this.wallpaperIds,
    required this.playbackMode,
    required this.intervalSeconds,
    required this.overlayOpacity,
  });

  final List<String> wallpaperIds;
  final WallpaperPlaybackMode playbackMode;
  final int intervalSeconds;
  final double overlayOpacity;

  @override
  State<BoardBackgroundLayer> createState() => _BoardBackgroundLayerState();
}

class _BoardBackgroundLayerState extends State<BoardBackgroundLayer> {
  final Random _random = Random();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant BoardBackgroundLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameIds(oldWidget.wallpaperIds, widget.wallpaperIds)) _index = 0;
    if (oldWidget.playbackMode != widget.playbackMode ||
        oldWidget.intervalSeconds != widget.intervalSeconds ||
        !_sameIds(oldWidget.wallpaperIds, widget.wallpaperIds)) {
      _restartTimer();
    }
  }

  bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.playbackMode != WallpaperPlaybackMode.random ||
        widget.wallpaperIds.length < 2) {
      return;
    }
    final seconds = ProjectSettings.clampWallpaperIntervalSeconds(
      widget.intervalSeconds,
    );
    _timer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!mounted || widget.wallpaperIds.length < 2) return;
      var next = _index;
      while (next == _index) {
        next = _random.nextInt(widget.wallpaperIds.length);
      }
      setState(() => _index = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.wallpaperIds.isEmpty) return const SizedBox.expand();
    if (_index >= widget.wallpaperIds.length) _index = 0;
    final opacity = ProjectSettings.clampOverlayOpacity(widget.overlayOpacity);
    return _BoardBackgroundImage(
      attachmentId: widget.wallpaperIds[_index],
      overlayOpacity: opacity,
    );
  }
}

class _BoardBackgroundImage extends StatefulWidget {
  const _BoardBackgroundImage({
    required this.attachmentId,
    required this.overlayOpacity,
  });

  final String attachmentId;
  final double overlayOpacity;

  @override
  State<_BoardBackgroundImage> createState() => _BoardBackgroundImageState();
}

class _BoardBackgroundImageState extends State<_BoardBackgroundImage> {
  Future<Uint8List?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _read();
  }

  @override
  void didUpdateWidget(covariant _BoardBackgroundImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachmentId != widget.attachmentId) _future = _read();
  }

  Future<Uint8List?> _read() {
    final controller = context.read<BoardController>();
    final isLibraryAsset =
        controller.wallpapers.any((item) => item.id == widget.attachmentId);
    return isLibraryAsset
        ? controller.readWallpaperBytes(widget.attachmentId, thumb: false)
        : controller.readAttachmentBytes(widget.attachmentId, thumb: false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return const SizedBox.expand();
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            ),
            if (widget.overlayOpacity > 0)
              ColoredBox(
                color: Colors.black.withValues(alpha: widget.overlayOpacity),
              ),
          ],
        );
      },
    );
  }
}
