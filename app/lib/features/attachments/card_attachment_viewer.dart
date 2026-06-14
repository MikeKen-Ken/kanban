import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import 'card_attachment_image.dart';

typedef CardAttachmentListChanged = void Function(List<CardAttachment> attachments);

Future<void> showCardAttachmentViewer({
  required BuildContext context,
  required List<CardAttachment> attachments,
  required int initialIndex,
  String? projectId,
  String? columnId,
  String? cardId,
  CardAttachmentListChanged? onAttachmentsChanged,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => _CardAttachmentViewer(
      attachments: [...attachments],
      initialIndex: initialIndex,
      projectId: projectId,
      columnId: columnId,
      cardId: cardId,
      onAttachmentsChanged: onAttachmentsChanged,
    ),
  );
}

class _CardAttachmentViewer extends StatefulWidget {
  const _CardAttachmentViewer({
    required this.attachments,
    required this.initialIndex,
    this.projectId,
    this.columnId,
    this.cardId,
    this.onAttachmentsChanged,
  });

  final List<CardAttachment> attachments;
  final int initialIndex;
  final String? projectId;
  final String? columnId;
  final String? cardId;
  final CardAttachmentListChanged? onAttachmentsChanged;

  @override
  State<_CardAttachmentViewer> createState() => _CardAttachmentViewerState();
}

class _CardAttachmentViewerState extends State<_CardAttachmentViewer> {
  late final PageController _pageController;
  late List<CardAttachment> _attachments;
  late int _index;
  bool _busy = false;

  bool get _canEdit =>
      widget.columnId != null &&
      widget.cardId != null &&
      widget.onAttachmentsChanged != null;

  @override
  void initState() {
    super.initState();
    _attachments = [...widget.attachments];
    _index = widget.initialIndex.clamp(0, _attachments.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onAttachmentsChanged?.call([..._attachments]);
  }

  Future<void> _setCover() async {
    if (!_canEdit || _busy || _index == 0) return;
    final controller = context.read<BoardController>();
    final attachment = _attachments[_index];
    setState(() => _busy = true);
    await controller.setCardAttachmentCover(
      widget.columnId!,
      widget.cardId!,
      attachment.id,
    );
    if (!mounted) return;
    final others = _attachments.where((a) => a.id != attachment.id).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    setState(() {
      _busy = false;
      _attachments = [
        attachment.copyWith(order: 0),
        for (var i = 0; i < others.length; i++) others[i].copyWith(order: i + 1),
      ];
      _index = 0;
    });
    _pageController.jumpToPage(0);
    _notifyChanged();
  }

  Future<void> _deleteCurrent() async {
    if (!_canEdit || _busy) return;
    final controller = context.read<BoardController>();
    final attachment = _attachments[_index];
    setState(() => _busy = true);
    await controller.removeCardAttachment(
      widget.columnId!,
      widget.cardId!,
      attachment.id,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _attachments = _attachments.where((a) => a.id != attachment.id).toList();
    });
    _notifyChanged();
    if (_attachments.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final nextIndex = _index.clamp(0, _attachments.length - 1);
    setState(() => _index = nextIndex);
    _pageController.jumpToPage(nextIndex);
  }

  @override
  Widget build(BuildContext context) {
    if (_attachments.isEmpty) {
      return const SizedBox.shrink();
    }

    final attachment = _attachments[_index];
    final isCover = _index == 0;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _attachments.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                final item = _attachments[index];
                return InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Center(
                    child: CardAttachmentImage(
                      attachmentId: item.id,
                      projectId: widget.projectId,
                      thumb: false,
                      fit: BoxFit.contain,
                      showMissingLabel: true,
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
            if (_attachments.length > 1)
              Positioned(
                bottom: _canEdit ? 88 : 24,
                left: 0,
                right: 0,
                child: Text(
                  '${_index + 1}/${_attachments.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            Positioned(
              top: 16,
              right: 16,
              child: Text(
                attachment.fileName,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            if (_canEdit)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Row(
                  children: [
                    if (!isCover)
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: _busy ? null : _setCover,
                          child: const Text('设为封面'),
                        ),
                      ),
                    if (!isCover) const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: _busy ? null : _deleteCurrent,
                        child: const Text('删除'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
