import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../wallpapers/wallpaper_models.dart';
import 'project_settings.dart';

/// 壁纸轮播切换时的渐变时长。
const _wallpaperFadeDuration = Duration(milliseconds: 800);

/// 看板全屏背景层。轮播只读取本地持久化缓存，不触发 WebDAV 请求。
class BoardBackgroundLayer extends StatefulWidget {
  const BoardBackgroundLayer({
    super.key,
    required this.wallpaperIds,
    required this.activeWallpaperId,
    required this.playbackMode,
    required this.intervalSeconds,
    required this.overlayOpacity,
  });

  final List<String> wallpaperIds;
  final String activeWallpaperId;
  final WallpaperPlaybackMode playbackMode;
  final int intervalSeconds;
  final double overlayOpacity;

  @override
  State<BoardBackgroundLayer> createState() => _BoardBackgroundLayerState();
}

class _BoardBackgroundLayerState extends State<BoardBackgroundLayer> {
  final Random _random = Random();
  Timer? _timer;

  String _resolveActiveId() {
    final ids = widget.wallpaperIds;
    if (ids.isEmpty) return '';
    final active = widget.activeWallpaperId;
    if (active.isNotEmpty && ids.contains(active)) return active;
    return ids.first;
  }

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant BoardBackgroundLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackMode != widget.playbackMode ||
        oldWidget.intervalSeconds != widget.intervalSeconds ||
        !_sameIds(oldWidget.wallpaperIds, widget.wallpaperIds) ||
        oldWidget.activeWallpaperId != widget.activeWallpaperId) {
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
      final current = _resolveActiveId();
      var next = current;
      while (next == current) {
        next = widget.wallpaperIds[_random.nextInt(widget.wallpaperIds.length)];
      }
      context.read<BoardController>().setActiveWallpaper(next);
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
    final opacity = ProjectSettings.clampOverlayOpacity(widget.overlayOpacity);
    final wallpaperId = _resolveActiveId();
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: _wallpaperFadeDuration,
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: StackFit.expand,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child: _BoardBackgroundImage(
            key: ValueKey(wallpaperId),
            attachmentId: wallpaperId,
          ),
        ),
        if (opacity > 0)
          ColoredBox(color: Colors.black.withValues(alpha: opacity)),
      ],
    );
  }
}

class _BoardBackgroundImage extends StatefulWidget {
  const _BoardBackgroundImage({
    super.key,
    required this.attachmentId,
  });

  final String attachmentId;

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
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
        );
      },
    );
  }
}
