import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';

/// 缩略图/原图字节的进程内缓存，避免拖拽重建时 FutureBuilder 先闪占位色。
class _AttachmentImageBytesCache {
  static const _maxEntries = 48;
  static const _maxBytes = 24 * 1024 * 1024;
  static final LinkedHashMap<String, Uint8List> _bytes = LinkedHashMap();
  static int _byteCount = 0;

  static String keyFor(String attachmentId,
          {required bool thumb, String? projectId}) =>
      '${projectId ?? ''}::$attachmentId::${thumb ? 1 : 0}';

  static Uint8List? get(String key) {
    final bytes = _bytes.remove(key);
    if (bytes != null) _bytes[key] = bytes;
    return bytes;
  }

  static void put(String key, Uint8List bytes) {
    final previous = _bytes.remove(key);
    if (previous != null) _byteCount -= previous.lengthInBytes;

    if (bytes.lengthInBytes > _maxBytes) return;
    while (_bytes.isNotEmpty &&
        (_bytes.length >= _maxEntries ||
            _byteCount + bytes.lengthInBytes > _maxBytes)) {
      final oldestKey = _bytes.keys.first;
      final removed = _bytes.remove(oldestKey);
      if (removed != null) _byteCount -= removed.lengthInBytes;
    }
    _bytes[key] = bytes;
    _byteCount += bytes.lengthInBytes;
  }
}

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
  Uint8List? _cachedBytes;

  String get _cacheKey => _AttachmentImageBytesCache.keyFor(
        widget.attachmentId,
        thumb: widget.thumb,
        projectId: widget.projectId,
      );

  void _beginLoad() {
    _cachedBytes = _AttachmentImageBytesCache.get(_cacheKey);
    _future = context
        .read<BoardController>()
        .readAttachmentBytes(
          widget.attachmentId,
          thumb: widget.thumb,
          projectId: widget.projectId,
        )
        .then((bytes) {
      if (bytes != null) {
        _AttachmentImageBytesCache.put(_cacheKey, bytes);
        _cachedBytes = bytes;
      }
      return bytes;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future == null) _beginLoad();
  }

  @override
  void didUpdateWidget(covariant CardAttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachmentId != widget.attachmentId ||
        oldWidget.thumb != widget.thumb ||
        oldWidget.projectId != widget.projectId) {
      _beginLoad();
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
        final bytes = snapshot.data ?? _cachedBytes;
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
          child = Image.memory(
            bytes,
            fit: widget.fit,
            gaplessPlayback: true,
          );
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
