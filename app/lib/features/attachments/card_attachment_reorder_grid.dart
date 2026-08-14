import 'package:flutter/material.dart';

import '../../models/kanban_models.dart';
import 'card_attachment_image.dart';

/// 长按触发排序的延迟（短于 Flutter 默认 500ms）。
const Duration kAttachmentReorderLongPressDelay = Duration(milliseconds: 200);

/// 可拖拽排序的卡片图片网格
class CardAttachmentReorderGrid extends StatelessWidget {
  const CardAttachmentReorderGrid({
    super.key,
    required this.attachments,
    required this.missingAttachmentIds,
    required this.onReorder,
    required this.onTap,
    required this.onMenu,
  });

  final List<CardAttachment> attachments;
  final Set<String> missingAttachmentIds;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onTap;
  final void Function(int index) onMenu;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < attachments.length; index++)
          _DraggableAttachmentTile(
            key: ValueKey(attachments[index].id),
            index: index,
            attachment: attachments[index],
            isCover: index == 0,
            isMissing: missingAttachmentIds.contains(attachments[index].id),
            onReorder: onReorder,
            onTap: () => onTap(index),
            onMenu: () => onMenu(index),
          ),
      ],
    );
  }
}

class _DraggableAttachmentTile extends StatelessWidget {
  const _DraggableAttachmentTile({
    super.key,
    required this.index,
    required this.attachment,
    required this.isCover,
    required this.isMissing,
    required this.onReorder,
    required this.onTap,
    required this.onMenu,
  });

  final int index;
  final CardAttachment attachment;
  final bool isCover;
  final bool isMissing;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  Widget _tile({required bool interactive}) {
    return _AttachmentTile(
      attachment: attachment,
      isCover: isCover,
      isMissing: isMissing,
      onTap: interactive ? onTap : null,
      onMenu: interactive ? onMenu : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tile = _tile(interactive: true);
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onReorder(details.data, index),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return LongPressDraggable<int>(
          data: index,
          delay: kAttachmentReorderLongPressDelay,
          hapticFeedbackOnStart: true,
          maxSimultaneousDrags: 1,
          feedback: Material(
            elevation: 8,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: Transform.scale(
              scale: 1.04,
              child: _tile(interactive: false),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: _tile(interactive: false),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: hovering
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: tile,
          ),
        );
      },
    );
  }
}

class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.isCover,
    required this.isMissing,
    this.onTap,
    this.onMenu,
  });

  final CardAttachment attachment;
  final bool isCover;
  final bool isMissing;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final canTap = widget.onTap != null;
    return SizedBox(
      width: 104,
      height: 104,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: canTap ? (_) => _setPressed(true) : null,
        onTapUp: canTap ? (_) => _setPressed(false) : null,
        onTapCancel: canTap ? () => _setPressed(false) : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CardAttachmentImage(
                  attachmentId: widget.attachment.id,
                  borderRadius: BorderRadius.circular(8),
                  showMissingLabel: widget.isMissing,
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  decoration: BoxDecoration(
                    color: _pressed ? Colors.black26 : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                if (widget.isCover)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '封面',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                if (widget.onMenu != null)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Material(
                      color: Colors.black45,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomLeft: Radius.circular(6),
                      ),
                      child: InkWell(
                        onTap: widget.onMenu,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomLeft: Radius.circular(6),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.more_vert,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                const Positioned(
                  right: 4,
                  bottom: 4,
                  child: IgnorePointer(
                    child: Icon(
                      Icons.drag_indicator,
                      size: 16,
                      color: Color(0xD9FFFFFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
