import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../attachments/picked_image_bytes.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

const _maxMcpImageBytes = 20 * 1024 * 1024;

/// 注册卡片图片附件的受控读写工具。
void registerKanbanMcpAttachmentTools(
  McpServer server,
  BoardController controller,
) {
  server.registerTool(
    'list_card_attachments',
    description: '列出卡片图片附件的元数据，不返回图片二进制。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'projectId': JsonSchema.string(description: '可选，缩小查找范围'),
      },
      required: ['cardId'],
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']);
      if (cardId == null) return mcpErrorResult('cardId 不能为空');
      final resolved = await resolveMcpProjectIdForCard(
        controller,
        cardId: cardId,
        projectId: args['projectId'] as String?,
      );
      if (resolved.error != null) return resolved.error!;
      return runMcpForProject(controller, resolved.projectId,
          (projectId) async {
        final card = _findCard(controller, cardId, resolved.columnId);
        if (card == null) return mcpErrorResult('未找到卡片：$cardId');
        final store = controller.attachmentStore;
        final localIds = store == null
            ? <String>{}
            : await store.listLocalAttachmentIds(projectId);
        return mcpJsonResult({
          'projectId': projectId,
          'cardId': cardId,
          'attachments': [
            for (final attachment in card.sortedAttachments)
              _attachmentJson(attachment,
                  local: localIds.contains(attachment.id)),
          ],
        });
      });
    },
  );

  server.registerTool(
    'read_card_attachment',
    description: '读取卡片图片附件，返回 JSON 元数据和 MCP 图片内容。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'attachmentId': JsonSchema.string(description: '图片附件 id'),
        'projectId': JsonSchema.string(description: '可选，缩小查找范围'),
        'thumbnail': JsonSchema.boolean(description: '是否读取缩略图，默认 false'),
      },
      required: ['cardId', 'attachmentId'],
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final cardId = mcpTrimmedString(args['cardId']);
      final attachmentId = mcpTrimmedString(args['attachmentId']);
      if (cardId == null || attachmentId == null) {
        return mcpErrorResult('cardId 和 attachmentId 不能为空');
      }
      final resolved = await resolveMcpProjectIdForCard(
        controller,
        cardId: cardId,
        projectId: args['projectId'] as String?,
      );
      if (resolved.error != null) return resolved.error!;
      return runMcpForProject(controller, resolved.projectId,
          (projectId) async {
        final card = _findCard(controller, cardId, resolved.columnId);
        final attachment =
            card?.attachments.where((a) => a.id == attachmentId).firstOrNull;
        if (attachment == null) return mcpErrorResult('未找到图片附件：$attachmentId');
        final store = controller.attachmentStore;
        if (store == null) return mcpErrorResult('当前平台不支持图片附件');
        final thumbnail = args['thumbnail'] == true;
        final bytes = await store.readBytes(
          projectId: projectId,
          attachmentId: attachmentId,
          thumb: thumbnail,
        );
        if (bytes == null || bytes.isEmpty) {
          return mcpErrorResult('图片文件不存在：$attachmentId');
        }
        final payload = _attachmentJson(attachment, local: true)
          ..['thumbnail'] = thumbnail;
        return CallToolResult(
          content: [
            TextContent(text: jsonEncode(payload)),
            ImageContent(
                data: base64Encode(bytes), mimeType: attachment.mimeType),
          ],
        );
      });
    },
  );

  server.registerTool(
    'add_card_attachment',
    description: '向卡片添加一张图片；imageBase64 只接受图片二进制的 base64。',
    inputSchema: _imageWriteSchema(),
    annotations: const ToolAnnotations(
        readOnlyHint: false, destructiveHint: false, openWorldHint: false),
    callback: (args, extra) async {
      final ids = await _resolveCardArgs(controller, args);
      if (ids.error != null) return ids.error!;
      final bytes = _decodeImage(args['imageBase64']);
      if (bytes == null) return mcpErrorResult('imageBase64 无效或超过 20 MB');
      return runMcpForProject(controller, ids.projectId, (projectId) async {
        final error = await controller.addCardAttachments(
          ids.columnId!,
          ids.cardId,
          pickImages: () async => [
            PickedImageBytes(
              bytes: bytes,
              fileName: mcpTrimmedString(args['fileName']) ?? 'image.jpg',
            ),
          ],
        );
        if (error != null) return mcpErrorResult(error);
        return _attachmentResult(
            controller, ids.cardId, ids.columnId!, projectId);
      });
    },
  );

  server.registerTool(
    'replace_card_attachment',
    description: '用新图片替换卡片中的指定图片附件。',
    inputSchema: _imageWriteSchema(
        extra: {'attachmentId': JsonSchema.string(description: '要替换的图片附件 id')}),
    annotations: const ToolAnnotations(
        readOnlyHint: false, destructiveHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final ids = await _resolveCardArgs(controller, args);
      final attachmentId = mcpTrimmedString(args['attachmentId']);
      if (ids.error != null) return ids.error!;
      if (attachmentId == null) return mcpErrorResult('attachmentId 不能为空');
      final bytes = _decodeImage(args['imageBase64']);
      if (bytes == null) return mcpErrorResult('imageBase64 无效或超过 20 MB');
      return runMcpForProject(controller, ids.projectId, (projectId) async {
        final card = _findCard(controller, ids.cardId, ids.columnId);
        final old =
            card?.attachments.where((a) => a.id == attachmentId).firstOrNull;
        final store = controller.attachmentStore;
        if (old == null) return mcpErrorResult('未找到图片附件：$attachmentId');
        if (store == null) return mcpErrorResult('当前平台不支持图片附件');
        final replacement = await store.saveImage(
          projectId: projectId,
          sourceBytes: bytes,
          fileName: mcpTrimmedString(args['fileName']) ?? old.fileName,
          order: old.order,
        );
        final next = [
          for (final attachment in card!.attachments)
            if (attachment.id == attachmentId)
              replacement.copyWith(order: attachment.order)
            else
              attachment,
        ];
        final error = await controller.updateCardFull(
          ids.columnId!,
          ids.cardId,
          attachments: next,
        );
        if (error != null) {
          await store.deleteAttachment(
              projectId: projectId, attachmentId: replacement.id);
          return mcpErrorResult(error);
        }
        await store.deleteAttachment(
            projectId: projectId, attachmentId: old.id);
        return _attachmentResult(
            controller, ids.cardId, ids.columnId!, projectId);
      });
    },
  );

  server.registerTool(
    'delete_card_attachment',
    description: '从卡片移除并删除指定图片附件的本地文件。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'attachmentId': JsonSchema.string(description: '图片附件 id'),
        'projectId': JsonSchema.string(description: '可选，缩小查找范围'),
      },
      required: ['cardId', 'attachmentId'],
    ),
    annotations: const ToolAnnotations(
        readOnlyHint: false, destructiveHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final ids = await _resolveCardArgs(controller, args);
      final attachmentId = mcpTrimmedString(args['attachmentId']);
      if (ids.error != null) return ids.error!;
      if (attachmentId == null) return mcpErrorResult('attachmentId 不能为空');
      return runMcpForProject(controller, ids.projectId, (projectId) async {
        final card = _findCard(controller, ids.cardId, ids.columnId);
        if (card == null ||
            !card.attachments.any((a) => a.id == attachmentId)) {
          return mcpErrorResult('未找到图片附件：$attachmentId');
        }
        await controller.removeCardAttachment(
            ids.columnId!, ids.cardId, attachmentId);
        return _attachmentResult(
            controller, ids.cardId, ids.columnId!, projectId);
      });
    },
  );

  server.registerTool(
    'set_card_attachment_cover',
    description: '将卡片中的指定图片设为封面。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'attachmentId': JsonSchema.string(description: '图片附件 id'),
        'projectId': JsonSchema.string(description: '可选，缩小查找范围'),
      },
      required: ['cardId', 'attachmentId'],
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: false, openWorldHint: false),
    callback: (args, extra) async {
      final ids = await _resolveCardArgs(controller, args);
      final attachmentId = mcpTrimmedString(args['attachmentId']);
      if (ids.error != null) return ids.error!;
      if (attachmentId == null) return mcpErrorResult('attachmentId 不能为空');
      return runMcpForProject(controller, ids.projectId, (projectId) async {
        final card = _findCard(controller, ids.cardId, ids.columnId);
        if (card == null ||
            !card.attachments.any((a) => a.id == attachmentId)) {
          return mcpErrorResult('未找到图片附件：$attachmentId');
        }
        await controller.setCardAttachmentCover(
            ids.columnId!, ids.cardId, attachmentId);
        return _attachmentResult(
            controller, ids.cardId, ids.columnId!, projectId);
      });
    },
  );

  server.registerTool(
    'reorder_card_attachments',
    description: '按 attachmentIds 给卡片图片重新排序，第一个元素成为封面。',
    inputSchema: JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'attachmentIds': JsonSchema.array(items: JsonSchema.string()),
        'projectId': JsonSchema.string(description: '可选，缩小查找范围'),
      },
      required: ['cardId', 'attachmentIds'],
    ),
    annotations:
        const ToolAnnotations(readOnlyHint: false, openWorldHint: false),
    callback: (args, extra) async {
      final ids = await _resolveCardArgs(controller, args);
      if (ids.error != null) return ids.error!;
      final requested = (args['attachmentIds'] as List<dynamic>?)
          ?.map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (requested == null || requested.isEmpty) {
        return mcpErrorResult('attachmentIds 不能为空');
      }
      return runMcpForProject(controller, ids.projectId, (projectId) async {
        final card = _findCard(controller, ids.cardId, ids.columnId);
        if (card == null ||
            requested.toSet().length != card.attachments.length ||
            !requested.toSet().containsAll(card.attachments.map((a) => a.id))) {
          return mcpErrorResult('attachmentIds 必须完整且不重复地包含卡片全部图片');
        }
        final byId = {
          for (final attachment in card.attachments) attachment.id: attachment
        };
        final next = [
          for (var i = 0; i < requested.length; i++)
            byId[requested[i]]!.copyWith(order: i)
        ];
        final error = await controller.updateCardFull(ids.columnId!, ids.cardId,
            attachments: next);
        if (error != null) return mcpErrorResult(error);
        return _attachmentResult(
            controller, ids.cardId, ids.columnId!, projectId);
      });
    },
  );
}

JsonObject _imageWriteSchema({Map<String, JsonSchema> extra = const {}}) =>
    JsonSchema.object(
      properties: {
        'cardId': JsonSchema.string(description: '卡片 id'),
        'projectId': JsonSchema.string(description: '可选，缩小查找范围'),
        'imageBase64': JsonSchema.string(description: '图片二进制 base64，最大 20 MB'),
        'fileName': JsonSchema.string(description: '图片文件名，仅作为元数据保存'),
        ...extra,
      },
      required: ['cardId', 'imageBase64', ...extra.keys],
    );

Uint8List? _decodeImage(Object? value) {
  final text = mcpTrimmedString(value);
  if (text == null) return null;
  try {
    final bytes = base64Decode(text);
    return bytes.length > _maxMcpImageBytes ? null : Uint8List.fromList(bytes);
  } on FormatException {
    return null;
  }
}

Map<String, dynamic> _attachmentJson(CardAttachment attachment,
        {required bool local}) =>
    {
      ...attachment.toJson(),
      'local': local,
      'cover': attachment.order == 0,
    };

KanbanCard? _findCard(
    BoardController controller, String cardId, String? columnId) {
  final board = controller.board;
  if (board == null) return null;
  for (final column in board.columns) {
    if (columnId != null && column.id != columnId) continue;
    for (final card in column.cards) {
      if (card.id == cardId) return card;
    }
  }
  return null;
}

Future<CallToolResult> _attachmentResult(
  BoardController controller,
  String cardId,
  String columnId,
  String projectId,
) async {
  final card = _findCard(controller, cardId, columnId);
  if (card == null) return mcpErrorResult('卡片不存在：$cardId');
  final store = controller.attachmentStore;
  final localIds = store == null
      ? <String>{}
      : await store.listLocalAttachmentIds(projectId);
  return mcpJsonResult({
    'ok': true,
    'projectId': projectId,
    'cardId': cardId,
    'attachments': [
      for (final attachment in card.sortedAttachments)
        _attachmentJson(attachment, local: localIds.contains(attachment.id)),
    ],
  });
}

Future<
        ({
          String cardId,
          String? projectId,
          String? columnId,
          CallToolResult? error
        })>
    _resolveCardArgs(
        BoardController controller, Map<String, dynamic> args) async {
  final cardId = mcpTrimmedString(args['cardId']);
  if (cardId == null) {
    return (
      cardId: '',
      projectId: null,
      columnId: null,
      error: mcpErrorResult('cardId 不能为空')
    );
  }
  final resolved = await resolveMcpProjectIdForCard(
    controller,
    cardId: cardId,
    projectId: args['projectId'] as String?,
  );
  return (
    cardId: cardId,
    projectId: resolved.projectId,
    columnId: resolved.columnId,
    error: resolved.error,
  );
}
