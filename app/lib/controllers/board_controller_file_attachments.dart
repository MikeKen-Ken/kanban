part of 'board_controller.dart';

extension BoardControllerFileAttachments on BoardController {
  Future<String?> addCardFileAttachments(
    String columnId,
    String cardId, {
    Future<List<PickedFileBytes>> Function()? pickFiles,
    bool allowOversized = false,
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
      if (store == null) return '当前平台不支持文件附件';

      final remaining =
          KanbanCard.maxFileAttachments - target.fileAttachments.length;
      if (remaining <= 0) {
        return '每张卡片最多 ${KanbanCard.maxFileAttachments} 个文件';
      }

      final picked = await (pickFiles ?? pickCardFiles)();
      if (picked.isEmpty) return null;

      final nextAttachments = [...target.fileAttachments];
      var nextOrder = nextAttachments.isEmpty
          ? 0
          : nextAttachments
                  .map((a) => a.order)
                  .reduce((a, b) => a > b ? a : b) +
              1;

      try {
        for (final file in picked) {
          if (nextAttachments.length >= KanbanCard.maxFileAttachments) break;
          if (!allowOversized && file.bytes.length > maxCardFileBytes) {
            return '单个文件不能超过 ${maxCardFileBytes ~/ (1024 * 1024)} MB';
          }
          final attachment = await store.saveFile(
            projectId: activeProjectId!,
            sourceBytes: file.bytes,
            fileName: file.fileName,
            order: nextOrder,
          );
          nextAttachments.add(attachment);
          nextOrder++;
        }
      } catch (_) {
        return '文件保存失败';
      }

      await updateCardFull(
        columnId,
        cardId,
        fileAttachments: nextAttachments,
      );
      unawaited(refreshMissingAttachments());
      return null;
    });
  }

  Future<void> removeCardFileAttachment(
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

      final nextAttachments = target.fileAttachments
          .where((attachment) => attachment.id != attachmentId)
          .toList();
      if (nextAttachments.length == target.fileAttachments.length) return;

      await updateCardFull(
        columnId,
        cardId,
        fileAttachments: _reindexFileAttachments(nextAttachments),
      );
      await attachmentStore?.deleteFileAttachment(
        projectId: activeProjectId!,
        attachmentId: attachmentId,
      );
      unawaited(refreshMissingAttachments());
      _markWorkspaceChanged();
    });
  }

  Future<String?> openCardFileAttachment(
    String columnId,
    String cardId,
    String attachmentId,
  ) async {
    if (activeProjectId == null) return '看板未就绪';
    final store = attachmentStore;
    if (store == null) return '当前平台不支持文件附件';

    KanbanCard? target;
    for (final col in board?.columns ?? const <KanbanColumn>[]) {
      if (col.id != columnId) continue;
      for (final card in col.cards) {
        if (card.id == cardId) {
          target = card;
          break;
        }
      }
    }
    if (target == null) return '卡片不存在';
    if (!target.fileAttachments.any((a) => a.id == attachmentId)) {
      return '文件不存在';
    }
    if (isAttachmentMissing(attachmentId)) {
      return '文件尚未同步到本机';
    }

    final path = await store.localFilePath(
      projectId: activeProjectId!,
      attachmentId: attachmentId,
    );
    if (path == null) return '文件尚未同步到本机';

    final opened = await card_file_opener.openCardFileAttachment(filePath: path);
    return opened ? null : '无法打开文件';
  }

  List<CardFileAttachment> _reindexFileAttachments(
    List<CardFileAttachment> attachments,
  ) {
    final sorted = [...attachments]..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(order: i),
    ];
  }

  Future<List<CardFileAttachment>> _copyCardFileAttachments(
    List<CardFileAttachment> sourceAttachments,
  ) async {
    final store = attachmentStore;
    final projectId = activeProjectId;
    if (store == null || projectId == null || sourceAttachments.isEmpty) {
      return sourceAttachments;
    }

    final orderedAttachments = [...sourceAttachments]
      ..sort((a, b) => a.order.compareTo(b.order));
    final copied = <CardFileAttachment>[];
    for (final attachment in orderedAttachments) {
      final bytes = await store.readFileBytes(
        projectId: projectId,
        attachmentId: attachment.id,
      );
      if (bytes == null) {
        copied.add(attachment);
        continue;
      }
      copied.add(
        await store.saveFile(
          projectId: projectId,
          sourceBytes: bytes,
          fileName: attachment.fileName,
          order: attachment.order,
          createdAt: attachment.createdAt,
        ),
      );
    }
    return copied;
  }

  Future<String?> copyCardFileAttachmentsBetweenProjects({
    required String fromProjectId,
    required String toProjectId,
    required List<CardFileAttachment> attachments,
  }) async {
    if (attachments.isEmpty) return null;
    final store = attachmentStore;
    if (store == null) return null;
    try {
      for (final attachment in attachments) {
        final bytes = await store.readFileBytes(
          projectId: fromProjectId,
          attachmentId: attachment.id,
        );
        if (bytes == null) continue;
        await store.writeFileBytes(
          projectId: toProjectId,
          attachmentId: attachment.id,
          bytes: bytes,
        );
      }
    } catch (error) {
      debugPrint('转移卡片文件附件失败：$error');
      return '转移文件附件失败';
    }
    return null;
  }
}
