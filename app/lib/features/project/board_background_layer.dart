import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import 'project_settings.dart';

/// 看板全屏背景层：图片使用 [BoxFit.cover] 铺满裁切，不拉伸变形
class BoardBackgroundLayer extends StatelessWidget {
  const BoardBackgroundLayer({
    super.key,
    required this.attachmentId,
    required this.overlayOpacity,
  });

  final String attachmentId;
  final double overlayOpacity;

  @override
  Widget build(BuildContext context) {
    final opacity = ProjectSettings.clampOverlayOpacity(overlayOpacity);
    return Stack(
      fit: StackFit.expand,
      children: [
        _BoardBackgroundImage(attachmentId: attachmentId),
        if (opacity > 0)
          ColoredBox(
            color: Colors.black.withValues(alpha: opacity),
          ),
      ],
    );
  }
}

class _BoardBackgroundImage extends StatefulWidget {
  const _BoardBackgroundImage({required this.attachmentId});

  final String attachmentId;

  @override
  State<_BoardBackgroundImage> createState() => _BoardBackgroundImageState();
}

class _BoardBackgroundImageState extends State<_BoardBackgroundImage> {
  Future<Uint8List?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= context.read<BoardController>().readAttachmentBytes(
          widget.attachmentId,
          thumb: false,
        );
  }

  @override
  void didUpdateWidget(covariant _BoardBackgroundImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachmentId != widget.attachmentId) {
      _future = context.read<BoardController>().readAttachmentBytes(
            widget.attachmentId,
            thumb: false,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const SizedBox.expand();
        }
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
