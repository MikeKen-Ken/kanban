part of 'board_controller.dart';

extension BoardControllerAttachments on BoardController {
  Future<String?> addCardAttachmentsFromSource(
    String columnId,
    String cardId,
    CardImageAddSource source,
  ) async {
    return _withBoardMutation(() async {
      final picked = await pickImagesForSource(source);
      if (picked.isEmpty) {
        return switch (source) {
          CardImageAddSource.clipboard => '剪贴板中没有图片',
          _ => null,
        };
      }
      return addCardAttachments(
        columnId,
        cardId,
        pickImages: () async => picked,
      );
    });
  }

  Future<String?> addCardAttachments(
    String columnId,
    String cardId, {
    Future<List<PickedImageBytes>> Function()? pickImages,
  }) async {
    return _withBoardMutation(() async {
      if (board == null || activeProjectId == null) return '看板未就绪';

      KanbanCard? target;
      for (final col in board!.columns) {
        if (col.id != columnId) continue;
        for (final card in col.cards) {
          if (card.id == cardId) {
            target = card;
            break;
          }
        }
      }
      if (target == null) return '卡片不存在';

      final store = attachmentStore;
      if (store == null) return '当前平台不支持图片附件';

      final remaining = KanbanCard.maxAttachments - target.attachments.length;
      if (remaining <= 0) {
        return '每张卡片最多 ${KanbanCard.maxAttachments} 张图片';
      }

      final picked = await (pickImages ?? pickCardImagesFromGallery)();
      if (picked.isEmpty) return null;

      final nextAttachments = [...target.attachments];
      var nextOrder = nextAttachments.isEmpty
          ? 0
          : nextAttachments
                  .map((a) => a.order)
                  .reduce((a, b) => a > b ? a : b) +
              1;

      try {
        for (final image in picked) {
          if (nextAttachments.length >= KanbanCard.maxAttachments) break;
          final attachment = await store.saveImage(
            projectId: activeProjectId!,
            sourceBytes: image.bytes,
            fileName: image.fileName,
            order: nextOrder,
          );
          nextAttachments.add(attachment);
          nextOrder++;
        }
      } catch (e) {
        return '图片处理失败';
      }

      await updateCardFull(
        columnId,
        cardId,
        attachments: nextAttachments,
      );
      await refreshMissingAttachments();
      return null;
    });
  }

  Future<void> reorderCardAttachments(
    String columnId,
    String cardId,
    List<CardAttachment> ordered,
  ) async {
    return _withBoardMutation(() async {
      await updateCardFull(
        columnId,
        cardId,
        attachments: _reindexAttachments(ordered),
      );
    });
  }

  Future<void> removeCardAttachment(
    String columnId,
    String cardId,
    String attachmentId,
  ) async {
    return _withBoardMutation(() async {
      if (board == null || activeProjectId == null) return;

      KanbanCard? target;
      for (final col in board!.columns) {
        if (col.id != columnId) continue;
        for (final card in col.cards) {
          if (card.id == cardId) {
            target = card;
            break;
          }
        }
      }
      if (target == null) return;

      final nextAttachments = target.attachments
          .where((attachment) => attachment.id != attachmentId)
          .toList();
      if (nextAttachments.length == target.attachments.length) return;

      await updateCardFull(
        columnId,
        cardId,
        attachments: _reindexAttachments(nextAttachments),
      );
      await attachmentStore?.deleteAttachment(
        projectId: activeProjectId!,
        attachmentId: attachmentId,
      );
      await refreshMissingAttachments();
      _markWorkspaceChanged();
    });
  }

  Future<void> setCardAttachmentCover(
    String columnId,
    String cardId,
    String attachmentId,
  ) async {
    return _withBoardMutation(() async {
      if (board == null) return;

      KanbanCard? target;
      for (final col in board!.columns) {
        if (col.id != columnId) continue;
        for (final card in col.cards) {
          if (card.id == cardId) {
            target = card;
            break;
          }
        }
      }
      if (target == null) return;

      final selected = target.attachments
          .where((attachment) => attachment.id == attachmentId)
          .toList();
      if (selected.isEmpty) return;

      final others = target.attachments
          .where((attachment) => attachment.id != attachmentId)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      final nextAttachments = [
        selected.first.copyWith(order: 0),
        for (var i = 0; i < others.length; i++)
          others[i].copyWith(order: i + 1),
      ];

      await updateCardFull(
        columnId,
        cardId,
        attachments: nextAttachments,
      );
    });
  }

  List<CardAttachment> _reindexAttachments(List<CardAttachment> attachments) {
    final sorted = [...attachments]..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(order: i),
    ];
  }
}

