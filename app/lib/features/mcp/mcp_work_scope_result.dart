import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../attachments/attachment_store.dart';
import '../kanban/next_work_card.dart';

const _maxInlineAttachmentBytes = 20 * 1024 * 1024;

/// 组装实施范围 JSON，并内联图片 ImageContent / 文件 base64。
Future<CallToolResult> mcpWorkScopeResult({
  required BoardController controller,
  required String projectId,
  required KanbanCard card,
  required Map<String, dynamic> basePayload,
  AttachmentStore? store,
}) {
  return mcpWorkScopeResultWithStore(
    store: store ?? controller.attachmentStore,
    projectId: projectId,
    card: card,
    basePayload: basePayload,
  );
}

/// 可注入 [store]，便于单测。
Future<CallToolResult> mcpWorkScopeResultWithStore({
  required AttachmentStore? store,
  required String projectId,
  required KanbanCard card,
  required Map<String, dynamic> basePayload,
}) async {
  final payload = <String, dynamic>{
    ...basePayload,
    ...buildCardWorkScope(card),
  };
  final images = <ImageContent>[];

  if (card.attachments.isNotEmpty) {
    final attachments = <Map<String, dynamic>>[];
    for (final attachment in card.sortedAttachments) {
      final meta = <String, dynamic>{
        ...attachment.toJson(),
        'cover': attachment.order == 0,
      };
      final bytes = await _safeReadBytes(
        store: store,
        projectId: projectId,
        attachmentId: attachment.id,
      );
      if (bytes != null &&
          bytes.isNotEmpty &&
          bytes.length <= _maxInlineAttachmentBytes) {
        meta['included'] = true;
        images.add(
          ImageContent(
            data: base64Encode(bytes),
            mimeType: attachment.mimeType,
          ),
        );
      } else {
        meta['included'] = false;
        if (bytes == null || bytes.isEmpty) {
          meta['missing'] = true;
        } else {
          meta['tooLarge'] = true;
        }
      }
      attachments.add(meta);
    }
    payload['attachments'] = attachments;
  }

  if (card.fileAttachments.isNotEmpty) {
    final files = <Map<String, dynamic>>[];
    for (final file in card.sortedFileAttachments) {
      final meta = <String, dynamic>{...file.toJson()};
      final bytes = await _safeReadFileBytes(
        store: store,
        projectId: projectId,
        attachmentId: file.id,
      );
      if (bytes != null &&
          bytes.isNotEmpty &&
          bytes.length <= _maxInlineAttachmentBytes) {
        meta['included'] = true;
        meta['contentBase64'] = base64Encode(bytes);
      } else {
        meta['included'] = false;
        if (bytes == null || bytes.isEmpty) {
          meta['missing'] = true;
        } else {
          meta['tooLarge'] = true;
        }
      }
      files.add(meta);
    }
    payload['fileAttachments'] = files;
  }

  if (card.attachments.isNotEmpty || card.fileAttachments.isNotEmpty) {
    payload['attachmentsNote'] =
        '附件已内联：图片为后续 ImageContent（顺序对应 attachments 中 included=true 的项）；'
        '文件为 fileAttachments[].contentBase64。无需再 list/read。';
  }

  return CallToolResult(
    content: [
      TextContent(text: jsonEncode(payload)),
      ...images,
    ],
  );
}

Future<Uint8List?> _safeReadBytes({
  required AttachmentStore? store,
  required String projectId,
  required String attachmentId,
}) async {
  if (store == null) return null;
  try {
    return await store.readBytes(
      projectId: projectId,
      attachmentId: attachmentId,
    );
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _safeReadFileBytes({
  required AttachmentStore? store,
  required String projectId,
  required String attachmentId,
}) async {
  if (store == null) return null;
  try {
    return await store.readFileBytes(
      projectId: projectId,
      attachmentId: attachmentId,
    );
  } catch (_) {
    return null;
  }
}
