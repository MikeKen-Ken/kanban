import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/attachments/attachment_store.dart';
import 'package:kanban/features/mcp/mcp_work_scope_result.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:mcp_dart/mcp_dart.dart';

class _MemoryAttachmentStore extends Fake implements AttachmentStore {
  _MemoryAttachmentStore(this._bytes);

  final Map<String, Uint8List> _bytes;

  @override
  Future<Uint8List?> readBytes({
    required String projectId,
    required String attachmentId,
    bool thumb = false,
  }) async =>
      _bytes[attachmentId];

  @override
  Future<Uint8List?> readFileBytes({
    required String projectId,
    required String attachmentId,
  }) async =>
      _bytes[attachmentId];
}

void main() {
  final tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  test('有图片时内联 ImageContent，文件内联 contentBase64', () async {
    const imageId = 'img-1';
    const fileId = 'file-1';
    final card = KanbanCard(
      id: 'c1',
      title: '带附件',
      order: 0,
      createdAt: 1,
      attachments: [
        CardAttachment(
          id: imageId,
          fileName: 'a.png',
          mimeType: 'image/png',
          order: 0,
          createdAt: 1,
        ),
      ],
      fileAttachments: [
        CardFileAttachment(
          id: fileId,
          fileName: 'note.txt',
          mimeType: 'text/plain',
          order: 0,
          createdAt: 1,
          size: 5,
        ),
      ],
    );

    final result = await mcpWorkScopeResultWithStore(
      store: _MemoryAttachmentStore({
        imageId: tinyPng,
        fileId: Uint8List.fromList(utf8.encode('hello')),
      }),
      projectId: 'p1',
      card: card,
      basePayload: {'cardId': 'c1'},
    );

    final text = result.content.whereType<TextContent>().single.text;
    final payload = jsonDecode(text) as Map<String, dynamic>;
    expect(payload['attachments'].single['included'], isTrue);
    expect(payload['fileAttachments'].single['included'], isTrue);
    expect(payload['fileAttachments'].single['contentBase64'],
        base64Encode(utf8.encode('hello')));
    expect(payload['attachmentsNote'], contains('已内联'));

    final images = result.content.whereType<ImageContent>().toList();
    expect(images, hasLength(1));
    expect(images.single.mimeType, 'image/png');
    expect(images.single.data, base64Encode(tinyPng));
  });

  test('缺文件时 included=false', () async {
    final card = KanbanCard(
      id: 'c1',
      title: '缺图',
      order: 0,
      createdAt: 1,
      attachments: [
        CardAttachment(
          id: 'missing',
          fileName: 'a.png',
          mimeType: 'image/png',
          order: 0,
          createdAt: 1,
        ),
      ],
    );

    final result = await mcpWorkScopeResultWithStore(
      store: _MemoryAttachmentStore({}),
      projectId: 'p1',
      card: card,
      basePayload: {'cardId': 'c1'},
    );
    final payload = jsonDecode(
      result.content.whereType<TextContent>().single.text,
    ) as Map<String, dynamic>;
    expect(payload['attachments'].single['included'], isFalse);
    expect(payload['attachments'].single['missing'], isTrue);
    expect(result.content.whereType<ImageContent>(), isEmpty);
  });
}
