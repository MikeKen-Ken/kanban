import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';

/// 从本地缓存加载卡片附件图片
class CardAttachmentImage extends StatefulWidget {
  const CardAttachmentImage({
    super.key,
    required this.attachmentId,
    this.projectId,
    this.thumb = true,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.showMissingLabel = false,
  });

  final String attachmentId;
  final String? projectId;
  final bool thumb;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool showMissingLabel;

  @override
  State<CardAttachmentImage> createState() => _CardAttachmentImageState();
}

class _CardAttachmentImageState extends State<CardAttachmentImage> {
  Future<Uint8List?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= context.read<BoardController>().readAttachmentBytes(
          widget.attachmentId,
          thumb: widget.thumb,
          projectId: widget.projectId,
        );
  }

  @override
  void didUpdateWidget(covariant CardAttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachmentId != widget.attachmentId ||
        oldWidget.thumb != widget.thumb ||
        oldWidget.projectId != widget.projectId) {
      _future = context.read<BoardController>().readAttachmentBytes(
            widget.attachmentId,
            thumb: widget.thumb,
            projectId: widget.projectId,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMissing = context.select<BoardController, bool>(
      (controller) =>
          widget.showMissingLabel &&
          controller.isAttachmentMissing(widget.attachmentId),
    );

    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        Widget child;
        if (bytes == null) {
          child = ColoredBox(
            color: colorScheme.surfaceContainerHighest,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isMissing ? Icons.cloud_off_outlined : Icons.image_outlined,
                    color: isMissing
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                  if (isMissing) ...[
                    const SizedBox(height: 4),
                    Text(
                      '缺失',
                      style: TextStyle(
                        color: colorScheme.error,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        } else {
          child = Image.memory(bytes, fit: widget.fit);
        }

        if (widget.borderRadius != null) {
          child = ClipRRect(
            borderRadius: widget.borderRadius!,
            child: child,
          );
        }
        return child;
      },
    );
  }
}
